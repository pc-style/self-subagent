# Cost Management & Token Budgeting

Effective subagent orchestration requires balancing performance with cost. Spawning 50 parallel agents on the most expensive model can deplete a budget in minutes.

This guide provides a framework for "Right Model, Right Task" allocation.

## Budget Tiers

Assign each task a tier based on its complexity and risk.

| Tier | Task Type | Recommended Model Class | Token Cap | Cost Est. (Input/Output) |
|------|-----------|-------------------------|-----------|--------------------------|
| **L1** | **Research** (Read-only) | Haiku, GPT-4o-mini, Flash | 2K | < $0.01 / task |
| **L2** | **Single File Edit** | Sonnet, GPT-4o, Opus | 4K | ~$0.05 / task |
| **L3** | **Architecture / Refactor** | Opus, o1, Sonnet 3.5 | 8K+ | ~$0.15 - $0.50 / task |

### L1: Research / Discovery
*   **Use for**: Grepping files, finding references, summarizing docs, listing file paths.
*   **Model**: Fast, cheap, high context window.
*   **Prompt Strategy**: "You are a read-only researcher. Do not write code. Output JSON."

### L2: Implementation (Standard)
*   **Use for**: Adding functions, fixing bugs, writing tests, single-file changes.
*   **Model**: Strong coding capabilities, good instruction following.
*   **Prompt Strategy**: "You are a focused executor. Edit only `src/foo.ts`."

### L3: Complex / Critical
*   **Use for**: Multi-file refactoring, API design, security-critical code, debugging subtle race conditions.
*   **Model**: Highest reasoning capability available.
*   **Prompt Strategy**: "You are a senior architect. Plan first, then execute. Verify deeply."

## Model Selection by CLI

Most CLIs allow model overrides via flags. Use these to enforce tiers.

### Amp
```bash
# L1
amp -x --model claude-3-haiku-20240307 "Find all usages of User..."
# L2
amp -x --model claude-3-5-sonnet-20240620 "Fix the bug in..."
# L3
amp -x --model claude-3-opus-20240229 "Refactor the auth system..."
```

### Claude Code
```bash
# L1
claude -p --model claude-3-haiku-20240307 "Scan for..."
# L2 (Default)
claude -p "Fix..."
# L3
claude -p --model claude-3-opus-20240229 "Redesign..."
```

### Codex
```bash
# L1
codex exec --model gpt-4o-mini "List files..."
# L2
codex exec --model gpt-4o "Implement..."
# L3
codex exec --model o1-preview "Solve complex logic..."
```

## Cost Tracking Script

Implement a simple tracker in your orchestration loop to prevent runaway costs.

```bash
#!/usr/bin/env bash
# cost-tracker.sh

COST_FILE="/tmp/subagent-costs.log"
LIMIT_USD=5.00

# Estimates per 1M tokens (Input / Output)
declare -A PRICE_IN=( ["haiku"]=0.25 ["sonnet"]=3.00 ["opus"]=15.00 ["gpt4o"]=2.50 ["mini"]=0.15 )
declare -A PRICE_OUT=( ["haiku"]=1.25 ["sonnet"]=15.00 ["opus"]=75.00 ["gpt4o"]=10.00 ["mini"]=0.60 )

track_usage() {
  local model="$1"
  local input_toks="$2"
  local output_toks="$3"
  
  # Normalize model name
  [[ "$model" == *"haiku"* ]] && model="haiku"
  [[ "$model" == *"sonnet"* ]] && model="sonnet"
  [[ "$model" == *"opus"* ]] && model="opus"
  [[ "$model" == *"gpt-4o"* ]] && model="gpt4o"
  [[ "$model" == *"mini"* ]] && model="mini"
  
  local p_in=${PRICE_IN[$model]:-3.00}
  local p_out=${PRICE_OUT[$model]:-15.00}
  
  # Calculate cost (awk for float math)
  local cost=$(awk "BEGIN {print ($input_toks * $p_in / 1000000) + ($output_toks * $p_out / 1000000)}")
  
  echo "$(date +%s):$model:$input_toks:$output_toks:$cost" >> "$COST_FILE"
}

check_budget() {
  if [[ -f "$COST_FILE" ]]; then
    local total=$(awk -F: '{sum+=$5} END {print sum}' "$COST_FILE")
    if (( $(echo "$total > $LIMIT_USD" | bc -l) )); then
      echo "CRITICAL: Budget exceeded (\$$total > \$$LIMIT_USD). Halting."
      exit 1
    fi
    echo "Current spend: \$$total"
  fi
}
```

## Prompt Optimization for Cost

1.  **Shared Context via Files**:
    Instead of pasting 500 lines of type definitions into *every* subagent prompt (500 * N tokens), write it to a file once.
    
    *Bad*:
    ```bash
    PROMPT="Here are the types: $(cat types.ts). Now write function X..."
    for i in {1..10}; do agent "$PROMPT"; done
    ```
    
    *Good*:
    ```bash
    cp types.ts /tmp/context.ts
    PROMPT="Read /tmp/context.ts for types. Now write function X..."
    for i in {1..10}; do agent "$PROMPT"; done
    ```

2.  **Specific Write Targets**:
    Telling an agent "Edit the code" forces it to read/index everything. Telling it "Edit src/utils.ts" allows it to ignore the rest (if the tool supports it), saving context window.

3.  **Resume vs. Restart**:
    Always try to resume a session on retry. Restarting requires re-reading the entire context.
    *   Claude: `--resume <session_id>`
    *   Codex: `exec resume <session_id>`

## Safety Limits

Hard limits to prevent "infinite loop" billing accidents:

1.  **Max Retries**: Never > 3. If it fails 3 times, the prompt is wrong or the task is too hard.
2.  **Max Duration**: `timeout` command is mandatory.
    *   L1: 120s
    *   L2: 300s
    *   L3: 600s
3.  **Max Parallelism**: Start small (3-5). Scaling to 50 linearly scales cost but rarely linearly scales value (due to merge conflicts and coordination overhead).