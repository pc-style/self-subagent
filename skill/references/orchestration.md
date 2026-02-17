# Advanced Orchestration Patterns

Beyond basic wave-based parallelism. These patterns are modeled on Amp's AgentRunner and ToolRunner internals.

## Dependency Graph Scheduler

The core scheduling algorithm. Maintains a graph of tasks and dispatches them as dependencies resolve. Includes diff-based verification and cost budgeting.

```
State machine per task:
  PENDING → RUNNING → DONE
                   → FAILED → RETRYING → DONE | ABANDONED
```

```bash
#!/usr/bin/env bash
# Dependency-aware parallel task scheduler with Cost & Quality Gates

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COST_TRACKER="$SCRIPT_DIR/../cost-tracker.sh"

# Source cost tracker if available (Upgrade #2)
if [[ -f "$COST_TRACKER" ]]; then
  source "$COST_TRACKER"
else
  check_budget() { return 0; }
  track_usage() { :; }
fi

declare -A TASK_STATUS    # id → pending|running|done|failed|abandoned
declare -A TASK_DEPS      # id → "dep1,dep2,dep3"
declare -A TASK_WRITES    # id → "file1,file2"
declare -A TASK_PIDS      # id → PID
declare -A TASK_PROMPTS   # id → prompt text
TASK_COMPLEXITY="medium"  # small|medium|large — used by diff verification

MAX_PARALLEL=6
TMPDIR=$(mktemp -d)

register_task() {
  local id="$1" deps="$2" writes="$3" prompt="$4"
  TASK_STATUS[$id]="pending"
  TASK_DEPS[$id]="$deps"
  TASK_WRITES[$id]="$writes"
  TASK_PROMPTS[$id]="$prompt"
}

deps_met() {
  local id="$1"
  local deps="${TASK_DEPS[$id]}"
  [[ -z "$deps" ]] && return 0
  for dep in ${deps//,/ }; do
    [[ "${TASK_STATUS[$dep]}" != "done" ]] && return 1
  done
  return 0
}

write_conflict() {
  local id="$1"
  local my_writes="${TASK_WRITES[$id]}"
  for other_id in "${!TASK_STATUS[@]}"; do
    [[ "${TASK_STATUS[$other_id]}" != "running" ]] && continue
    for my_file in ${my_writes//,/ }; do
      for other_file in ${TASK_WRITES[$other_id]//,/ }; do
        [[ "$my_file" == "$other_file" ]] && return 0  # conflict!
      done
    done
  done
  return 1  # no conflict
}

count_running() {
  local n=0
  for s in "${TASK_STATUS[@]}"; do [[ "$s" == "running" ]] && ((n++)); done
  echo $n
}

all_terminal() {
  for s in "${TASK_STATUS[@]}"; do
    [[ "$s" != "done" && "$s" != "abandoned" ]] && return 1
  done
  return 0
}

dispatch_ready() {
  # Budget Check (Upgrade #2)
  if ! check_budget; then
    # If budget exceeded, don't start new tasks, but let running ones finish
    return
  fi

  for id in "${!TASK_STATUS[@]}"; do
    [[ "${TASK_STATUS[$id]}" != "pending" ]] && continue
    (( $(count_running) >= MAX_PARALLEL )) && return
    deps_met "$id" || continue
    write_conflict "$id" && continue

    # Launch
    TASK_STATUS[$id]="running"
    # Note: If CLI supports JSON output, we could pipe to a handler to extract token usage
    timeout 300 $AGENT_CMD "${TASK_PROMPTS[$id]}" > "$TMPDIR/$id.out" 2>&1 &
    TASK_PIDS[$id]=$!
  done
}

reap_finished() {
  for id in "${!TASK_STATUS[@]}"; do
    [[ "${TASK_STATUS[$id]}" != "running" ]] && continue
    local pid="${TASK_PIDS[$id]}"
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid"
      local exit_code=$?

      # Cost Tracking (Upgrade #2)
      # If we can parse tokens from output (depends on CLI), track it here:
      # track_usage "claude-3-sonnet" $INPUT_TOKENS $OUTPUT_TOKENS "$id"

      if (( exit_code != 0 )); then
        TASK_STATUS[$id]="failed"
        continue
      fi

      # --- Diff-Based Verification (Upgrade #7) ---
      # Before marking done, verify the diff is clean:
      #   - No secrets/credentials introduced
      #   - Only declared write targets modified
      #   - Diff size proportional to task complexity
      local verify_exit=0
      if [[ -x "$SCRIPT_DIR/diff-verify.sh" ]]; then
        "$SCRIPT_DIR/diff-verify.sh" \
          "$TMPDIR" \
          "$TMPDIR/$id-results" \
          "${TASK_WRITES[$id]//,/ }" \
          "${TASK_COMPLEXITY:-medium}" || verify_exit=$?
      fi

      case $verify_exit in
        0)
          # Diff clean — now run the full quality gate
          local gate_exit=0
          "$SCRIPT_DIR/../quality-gate.sh" \
            "$TMPDIR" \
            "$TMPDIR/$id-results" \
            "${TASK_WRITES[$id]//,/ }" \
            "${TASK_COMPLEXITY:-medium}" || gate_exit=$?

          if (( gate_exit == 0 )); then
            TASK_STATUS[$id]="done"
          else
            TASK_STATUS[$id]="failed"
          fi
          ;;
        2)
          # SECRETS FOUND — hard block, already auto-reverted
          echo "BLOCKED: Secrets detected in $id — changes reverted"
          TASK_STATUS[$id]="failed"
          ;;
        *)
          # Rogue edits or oversized diff — already auto-reverted
          echo "REJECTED: Diff verification failed for $id — changes reverted"
          TASK_STATUS[$id]="failed"
          ;;
      esac
    fi
  done
}

# Main loop
run_all() {
  while ! all_terminal; do
    reap_finished
    dispatch_ready

    # Promote failed → abandoned (after 1 retry, parent handles it)
    for id in "${!TASK_STATUS[@]}"; do
      [[ "${TASK_STATUS[$id]}" == "failed" ]] && TASK_STATUS[$id]="abandoned"
    done

    sleep 1
  done
}
```

Usage:
```bash
register_task "log-auth"   ""          "src/auth.ts"           "ROLE: executor ..."
register_task "log-pay"    ""          "src/payments.ts"       "ROLE: executor ..."
register_task "test-auth"  "log-auth"  "tests/auth.test.ts"    "ROLE: executor ..."
register_task "test-pay"   "log-pay"   "tests/payments.test.ts" "ROLE: executor ..."
register_task "ci"         "test-auth,test-pay" ".github/ci.yml" "ROLE: executor ..."
run_all
```

The scheduler automatically computes waves, respects dependencies, prevents write conflicts, checks budget limits, and throttles concurrency.

## Streaming Results (Process as They Complete)

Don't wait for all tasks — act on results as they arrive:

```bash
FIFO=$(mktemp -u)
mkfifo "$FIFO"

# Collector runs in background, processes results as they arrive
(while read -r line; do
  TASK_ID=$(echo "$line" | cut -d: -f1)
  STATUS=$(echo "$line" | cut -d: -f2)
  echo "[$(date +%H:%M:%S)] $TASK_ID: $STATUS"

  if [[ "$STATUS" == "done" ]]; then
    # Immediately dispatch dependents
    dispatch_ready
  fi
done < "$FIFO") &
COLLECTOR_PID=$!

# Each subagent writes to the FIFO on completion
spawn_with_notify() {
  local id="$1" prompt="$2"
  (
    timeout 300 $AGENT_CMD "$prompt" > "$TMPDIR/$id.out" 2>&1
    echo "$id:$([ $? -eq 0 ] && echo done || echo failed)" > "$FIFO"
  ) &
}
```

## Git Worktree Isolation

When tasks MUST write to overlapping files, give each subagent its own working copy:

```bash
PROJECT=$(git rev-parse --show-toplevel)
WORKTREE_BASE="/tmp/subagent-worktrees"

create_worktree() {
  local id="$1"
  local dir="$WORKTREE_BASE/$id"
  git worktree add "$dir" -b "subagent/$id" HEAD --quiet
  echo "$dir"
}

remove_worktree() {
  local id="$1"
  git worktree remove "$WORKTREE_BASE/$id" --force 2>/dev/null
  git branch -D "subagent/$id" 2>/dev/null
}

# Spawn in isolated worktrees
WT_A=$(create_worktree "task-a")
WT_B=$(create_worktree "task-b")

(cd "$WT_A" && $AGENT_CMD "Refactor auth module...") > "$TMPDIR/a.out" 2>&1 &
(cd "$WT_B" && $AGENT_CMD "Refactor payments module...") > "$TMPDIR/b.out" 2>&1 &
wait

# Merge results back
cd "$PROJECT"
git merge subagent/task-a --no-edit
git merge subagent/task-b --no-edit

# Cleanup
remove_worktree "task-a"
remove_worktree "task-b"
```

Use worktrees when:
- Two tasks must modify the same file independently
- Tasks need to run `npm install` or other setup that modifies lockfiles
- You want full git-level isolation and easy rollback

## Chained Pipeline

Sequential stages where each stage's output feeds the next. Only the final stage writes code.

```bash
# Stage 1: Research (read-only, parallel fan-out)
R1=$(timeout 120 $AGENT_CMD "ROLE: researcher. Find all API routes in src/routes/. Output as JSON array.")
R2=$(timeout 120 $AGENT_CMD "ROLE: researcher. Find all middleware in src/middleware/. Output as JSON array.")

# Stage 2: Plan (read-only, uses research)
PLAN=$(timeout 180 $AGENT_CMD "ROLE: planner. Given these routes:
$R1
And these middleware:
$R2
Create a plan to add rate limiting. Output as numbered task list with exact files and changes.")

# Stage 3: Execute (parallel fan-out using the plan)
# Parse PLAN into individual tasks and spawn in parallel
# (use the wave scheduler from above)
```

Pipeline patterns:
- **Research → Execute**: 2 stages, most common
- **Research → Plan → Execute**: 3 stages, for complex multi-file changes
- **Research → Plan → Execute → Review**: 4 stages, highest quality but slowest

## Error Recovery with Context Injection

When retrying, inject the failure context so the subagent can fix its own mistake:

```bash
retry_with_context() {
  local id="$1" original_prompt="$2" max_retries="${3:-1}"
  local attempt=0 exit_code
  local session_id=""

  while (( attempt <= max_retries )); do
    local prompt="$original_prompt"
    local use_resume=false

    if (( attempt > 0 )); then
      local prev_log="$TMPDIR/$id.attempt$((attempt-1)).out"
      local prev_error=$(tail -80 "$prev_log")
      
      # Detect Session ID (Claude Code pattern: "Session ID: <uuid>")
      session_id=$(grep -oE "Session ID: [a-zA-Z0-9-]+" "$prev_log" 2>/dev/null | awk '{print $NF}' | tail -1 || true)
      
      local fix_instructions="RETRY (attempt $((attempt+1))). Previous attempt failed.
Error output (last 80 lines):
$prev_error

Fix the issue. Do not repeat the same mistake."

      # Enable resume if supported and session ID found
      if [[ -n "$session_id" ]]; then
        if [[ "$AGENT_CMD" == *"claude"* ]]; then
          use_resume=true
        fi
      fi

      if [[ "$use_resume" == "true" ]]; then
        # For resume, we only send the fix instructions, not the whole context
        prompt="$fix_instructions"
      else
        # Fallback: Full context injection (Restart)
        local prev_diff=$(cd "$PROJECT" && git diff --stat 2>/dev/null)
        prompt="$original_prompt

$fix_instructions

Files changed so far:
$prev_diff"
      fi
    fi

    # Execute
    if [[ "$use_resume" == "true" ]]; then
      # Resume session (cheaper, faster)
      # Assumes AGENT_CMD allows appending --resume (works for Claude)
      timeout 300 $AGENT_CMD --resume "$session_id" "$prompt" > "$TMPDIR/$id.attempt$attempt.out" 2>&1
    else
      # Standard execution (fresh session)
      timeout 300 $AGENT_CMD "$prompt" > "$TMPDIR/$id.attempt$attempt.out" 2>&1
    fi

    exit_code=$?
    (( exit_code == 0 )) && { cp "$TMPDIR/$id.attempt$attempt.out" "$TMPDIR/$id.out"; return 0; }
    ((attempt++))
  done
  return 1
}
```

## Throttle Governor

Limit concurrent subagents. Uses `wait -n` to detect the first finished child and immediately dispatch the next ready task:

```bash
MAX_PARALLEL=4

throttled_dispatch() {
  local -a queue=("$@")  # array of "id:prompt" pairs
  local running=0

  for entry in "${queue[@]}"; do
    local id="${entry%%:*}"
    local prompt="${entry#*:}"

    while (( running >= MAX_PARALLEL )); do
      wait -n 2>/dev/null  # wait for ANY one child to finish
      ((running--))
    done

    timeout 300 $AGENT_CMD "$prompt" > "$TMPDIR/$id.out" 2>&1 &
    ((running++))
  done

  wait  # drain remaining
}
```

## Structured Output Collection

When subagents support JSON output, collect into a manifest for programmatic analysis:

```bash
# Spawn with JSON output (Claude example)
for id in task1 task2 task3; do
  claude -p --output-format json --dangerously-skip-permissions \
    "$(cat prompts/$id.txt)" > "$TMPDIR/$id.json" 2>/dev/null &
done
wait

# Build manifest
jq -n --slurpfile t1 "$TMPDIR/task1.json" \
      --slurpfile t2 "$TMPDIR/task2.json" \
      --slurpfile t3 "$TMPDIR/task3.json" \
  '{tasks: [
    {id:"task1", result: $t1[0].result, cost: $t1[0].cost_usd},
    {id:"task2", result: $t2[0].result, cost: $t2[0].cost_usd},
    {id:"task3", result: $t3[0].result, cost: $t3[0].cost_usd}
  ]}' > "$TMPDIR/manifest.json"
```

## Timeout Guidelines

| Task type | Timeout | Rationale |
|-----------|---------|-----------|
| Read-only research | 120s | Mostly I/O, should be fast |
| Single-file edit | 180s | Read + think + write |
| Multi-file implementation | 300s | Multiple read/write cycles |
| Complex refactor | 600s | Deep analysis + many edits |
| Full feature (10+ files) | 900s max | If it takes longer, break it into smaller tasks |

On macOS, if `timeout` isn't available:
```bash
brew install coreutils  # provides gtimeout
alias timeout=gtimeout
```
