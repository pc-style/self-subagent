#!/usr/bin/env bash
# Test harness runner for Claude Code
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(dirname "$SCRIPT_DIR")"
SCENARIO="${1:-01-error-handling}"
RUN_ID="$(date +%s)"
RESULTS_DIR="$HARNESS_DIR/results/claude-$RUN_ID"

mkdir -p "$RESULTS_DIR"

echo "========================================"
echo "Testing Claude Code"
echo "Scenario: $SCENARIO"
echo "Results: $RESULTS_DIR"
echo "========================================"

# Check if claude is available
if ! command -v claude &>/dev/null; then
  echo "ERROR: claude command not found"
  exit 1
fi

# Create temp copy of sample repo
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cp -r "$HARNESS_DIR/sample-repo" "$TMPDIR/repo"
cd "$TMPDIR/repo"

# Initialize git (required for Claude Code)
git init --quiet
git add .
git commit -m "Initial commit" --quiet

echo ""
echo "Sample repo initialized at: $TMPDIR/repo"
echo "Starting test at: $(date)"
echo ""

START_TIME=$(date +%s)

# Read the scenario prompt
PROMPT=$(cat "$HARNESS_DIR/scenarios/$SCENARIO/prompt.txt")

# Run Claude Code with the self-subagent skill
echo "Running Claude Code with self-subagent..."
echo "This may take 5-10 minutes..."
echo ""

# macOS compatible timeout
if command -v gtimeout &>/dev/null; then
  TIMEOUT_CMD="gtimeout 600"
elif command -v timeout &>/dev/null; then
  TIMEOUT_CMD="timeout 600"
else
  echo "Warning: timeout not available, running without timeout"
  TIMEOUT_CMD=""
fi

$TIMEOUT_CMD claude -p --dangerously-skip-permissions "
You are an expert in parallel code execution using the self-subagent skill.

Your task:
$PROMPT

Working directory: $TMPDIR/repo

Follow the self-subagent SKILL.md protocol exactly:
1. First discover your execute mode (claude -p --dangerously-skip-permissions)
2. Decompose the task into a dependency graph
3. Spawn parallel subagents for each independent module
4. Collect and verify results
5. Run typecheck to validate changes

IMPORTANT:
- Spawn up to 5 parallel subagents (one per module)
- Each subagent should handle one file
- Wait for all subagents to complete
- Verify with: npx tsc --noEmit
- Report which files were modified and any errors encountered
" > "$RESULTS_DIR/output.log" 2>&1 &
echo $! > "$RESULTS_DIR/pid"

wait $(cat "$RESULTS_DIR/pid")
EXIT_CODE=$?
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "========================================"
echo "Test completed"
echo "Duration: ${DURATION}s"
echo "Exit code: $EXIT_CODE"
echo "========================================"

# Save results
echo "$EXIT_CODE" > "$RESULTS_DIR/exit_code"
echo "$START_TIME" > "$RESULTS_DIR/start_time"
echo "$END_TIME" > "$RESULTS_DIR/end_time"
echo "$DURATION" > "$RESULTS_DIR/duration"

# Copy modified files
cp -r "$TMPDIR/repo/src" "$RESULTS_DIR/modified_src"
cd "$TMPDIR/repo"
git diff --name-only > "$RESULTS_DIR/modified_files.txt" 2>/dev/null || echo "No git changes" > "$RESULTS_DIR/modified_files.txt"
git diff > "$RESULTS_DIR/git_diff.patch" 2>/dev/null || echo "No diff" > "$RESULTS_DIR/git_diff.patch"

# Run scoring
echo ""
echo "Running scoring..."
"$HARNESS_DIR/score-discovery.sh" "$TMPDIR/repo" "$SCENARIO" "$RESULTS_DIR"
"$HARNESS_DIR/score-correctness.sh" "$TMPDIR/repo" "$RESULTS_DIR"
"$HARNESS_DIR/score-parallelism.sh" "$RESULTS_DIR" 5

echo ""
echo "Results saved to: $RESULTS_DIR"
echo ""
cat "$RESULTS_DIR/scorecard.txt"