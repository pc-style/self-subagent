#!/usr/bin/env bash
# Test harness runner for Amp CLI
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(dirname "$SCRIPT_DIR")"
SCENARIO="${1:-01-error-handling}"
RUN_ID="$(date +%s)"
RESULTS_DIR="$HARNESS_DIR/results/amp-$RUN_ID"

mkdir -p "$RESULTS_DIR"

echo "========================================"
echo "Testing Amp CLI"
echo "Scenario: $SCENARIO"
echo "Results: $RESULTS_DIR"
echo "========================================"

# Check if amp is available
if ! command -v amp &>/dev/null; then
  echo "ERROR: amp command not found"
  exit 1
fi

# Create temp copy of sample repo
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cp -r "$HARNESS_DIR/sample-repo" "$TMPDIR/repo"
cd "$TMPDIR/repo"

# Initialize git
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

# Run Amp with the self-subagent skill
echo "Running Amp with self-subagent..."
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

$TIMEOUT_CMD amp -x --dangerously-allow-all "
Use the self-subagent skill to:
$PROMPT

Working directory: $TMPDIR/repo

Follow the self-subagent protocol:
1. Decompose into parallel tasks (one per module)
2. Spawn subagents using amp -x
3. Collect results and verify with typecheck
4. Report which files were modified
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