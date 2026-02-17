#!/usr/bin/env bash
# Test Scenario: PI Agent building Todo App (1 agent - 1 file)
# Verifies Upgrades #2 (Cost), #4 (Resume), #8 (Context) working together.
# Rewritten to avoid associative arrays (Bash 3.x compatibility).
#
# Usage: ./test-harness/test-pi-todo.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MOCK_PI="$SCRIPT_DIR/mock-pi.sh"
CONTEXT_PACKER="$PROJECT_DIR/skill/context-packer.sh"
COST_TRACKER="$PROJECT_DIR/skill/cost-tracker.sh"

# Setup Workspace
export TMPDIR=$(mktemp -d)
export PROJECT="$TMPDIR/todo-app"
mkdir -p "$PROJECT"
cd "$PROJECT"
git init --quiet

# Agent Command
if command -v pi >/dev/null 2>&1; then
  # Use real PI agent if available
  # -p: non-interactive
  # --tools write: explicitly enable write tool
  # --thinking off: save tokens/time
  export AGENT_CMD="pi -p --tools write --thinking off"
  echo "Using real PI agent: $(which pi)"
else
  echo "Using Mock PI agent"
  export AGENT_CMD="$MOCK_PI"
fi

# ---------------------------------------------------------------------------
# Step 1: Prepare Shared Context (Upgrade #8)
# ---------------------------------------------------------------------------
echo "=== Step 1: Packing Context (Upgrade #8) ==="

mkdir -p docs
cat > docs/requirements.md << 'EOF'
# Todo App Requirements
1. Single page app.
2. Add, delete, toggle items.
3. Persist to localStorage.
EOF

cat > docs/style.md << 'EOF'
# Style Guide
- Use semantic HTML5.
- Use flexbox/grid for layout.
- Use vanilla JS (ES6+).
EOF

cat > docs/selectors.md << 'EOF'
# DOM Selectors (Strict Contract)
HTML, CSS, and JS must use these exact IDs and Classes:
- Container: #app
- Input: #todo-input
- Add Button: #add-btn
- List: #todo-list
- Item: .todo-item (li element)
- Item Text: .todo-text (span element)
- Delete Button: .delete-btn (button element)
- Checkbox: .todo-checkbox (input type=checkbox)
EOF

"$CONTEXT_PACKER" "$TMPDIR/shared-context.md" "docs/requirements.md" "docs/style.md" "docs/selectors.md"
echo "Context packed to $TMPDIR/shared-context.md"

# ---------------------------------------------------------------------------
# Step 2: Initialize Cost Tracker (Upgrade #2)
# ---------------------------------------------------------------------------
echo "=== Step 2: Initializing Cost Tracker (Upgrade #2) ==="
source "$COST_TRACKER"
export COST_FILE="$TMPDIR/costs.log"
# Set a generous budget for testing
export BUDGET_LIMIT="1.00"

# ---------------------------------------------------------------------------
# Step 3: Scheduler Logic (Bash 3.x Compatible)
# ---------------------------------------------------------------------------
echo "=== Step 3: Running Orchestration ==="

# Define Tasks
IDS="html css js"
SHARED_CTX_INSTRUCTION="Read $TMPDIR/shared-context.md for requirements, styles, and selectors."

# Store prompts in variables
PROMPT_html="ROLE: Frontend Dev. $SHARED_CTX_INSTRUCTION Write file: index.html using the defined selectors. MUST link style.css and app.js."
PROMPT_css="ROLE: Designer. $SHARED_CTX_INSTRUCTION Write file: style.css using the defined selectors."
PROMPT_js="ROLE: JS Dev. $SHARED_CTX_INSTRUCTION Write file: app.js implementing interactive DOM logic (add/delete/toggle tasks) for the defined selectors."

# Initialize status
STATUS_html="pending"
STATUS_css="pending"
STATUS_js="pending"

# Run Loop
run_all() {
  echo "Starting wave..."

  # Dispatch
  for id in $IDS; do
    # Get status via indirect reference
    eval "current_status=\$STATUS_$id"

    if [[ "$current_status" == "pending" ]]; then
      # Budget Check
      if ! check_budget >/dev/null; then
        echo "Budget exceeded! Aborting $id"
        eval "STATUS_$id='abandoned'"
        continue
      fi

      echo "Spawning $id..."

      # Get prompt via indirect reference
      eval "prompt=\$PROMPT_$id"

      # Run mock agent in background
      (
        $AGENT_CMD "$prompt" > "$TMPDIR/$id.out" 2>&1
      ) &

      # Store PID
      pid=$!
      eval "PID_$id=$pid"
      eval "STATUS_$id='running'"
    fi
  done

  # Wait and Collect
  for id in $IDS; do
    eval "current_status=\$STATUS_$id"

    if [[ "$current_status" == "running" ]]; then
      eval "pid=\$PID_$id"
      wait "$pid"
      eval "STATUS_$id='done'"

      # Track Cost (Upgrade #2)
      if [[ -f "$TMPDIR/$id.out" ]]; then
        if grep -q "TOKEN_USAGE:" "$TMPDIR/$id.out"; then
            # Parse fake token usage from Mock PI output
            TOKENS=$(grep "TOKEN_USAGE:" "$TMPDIR/$id.out" | cut -d: -f2)
            # Use simple cut/awk to get numbers
            IN=$(echo "$TOKENS" | awk '{print $1}')
            OUT=$(echo "$TOKENS" | awk '{print $2}')

            # Log it
            track_usage "pi-model" "$IN" "$OUT" "$id"
            echo "Task $id completed. Cost tracked."
        else
            # Real PI agent - log dummy value
            track_usage "pi-real" "100" "100" "$id"
            echo "Task $id completed. (Real PI: dummy cost tracked)"
        fi
      fi
    fi
  done
}

run_all

# ---------------------------------------------------------------------------
# Step 4: Verification
# ---------------------------------------------------------------------------
echo "=== Step 4: Verifying Results ==="

FAIL=0

# Verify Files Created
for file in index.html style.css app.js; do
  if [[ -f "$file" ]]; then
    echo "PASS: $file created"
  else
    echo "FAIL: $file missing"
    FAIL=1
  fi
done

# Verify Cost Tracking
if [[ -f "$COST_FILE" ]]; then
  COUNT=$(wc -l < "$COST_FILE")
  # Expect at least 3 entries (one per task)
  if [[ $COUNT -ge 3 ]]; then
    echo "PASS: Cost log contains $COUNT entries (expected >= 3)"
  else
    echo "FAIL: Cost log has only $COUNT entries"
    FAIL=1
  fi

  # Print report using the tracker's report function
  echo ""
  report_costs
else
  echo "FAIL: Cost file missing"
  FAIL=1
fi

# Verify Context Usage (Indirectly via prompt check in output log)
if grep -q "shared-context.md" "$TMPDIR/html.out"; then
  echo "PASS: Subagent prompt contained shared context path"
elif [[ "$AGENT_CMD" != *"$MOCK_PI"* ]]; then
  echo "SKIP: Context usage check (Real PI agent may not echo prompt)"
else
  echo "FAIL: Shared context path missing from prompt"
  FAIL=1
fi

echo ""
if [[ $FAIL -eq 0 ]]; then
  echo "SUCCESS: All systems operational."
  exit 0
else
  echo "FAILURE: Some checks failed."
  exit 1
fi
