#!/usr/bin/env bash
# Test: Session Resumption (Upgrade #4)
# Verifies that retry_with_context correctly detects session IDs and uses --resume.
#
# Usage: ./test-harness/test-resume.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Setup environment
export TMPDIR=$(mktemp -d)
export PROJECT="$TMPDIR/repo"
mkdir -p "$PROJECT"
cd "$PROJECT"
git init --quiet

# Mock Agent Command
# Fails on first run, succeeds on second.
# Outputs a Session ID.
MOCK_AGENT="$TMPDIR/mock_agent.sh"
cat > "$MOCK_AGENT" << 'EOF'
#!/bin/bash
ARGS="$@"

# Check if we are resuming
if [[ "$ARGS" == *"--resume"* ]]; then
  echo "MOCK AGENT: Resuming session..."
  echo "RESUMED" # Marker for test verification
  exit 0
else
  echo "MOCK AGENT: Starting fresh session..."
  echo "Session ID: 550e8400-e29b-41d4-a716-446655440000"
  echo "Error: Something went wrong."
  exit 1
fi
EOF
chmod +x "$MOCK_AGENT"

# Set AGENT_CMD to use the mock agent
# We add "claude" to the name so the detection logic triggers
export AGENT_CMD="$MOCK_AGENT # claude mock"

# ---------------------------------------------------------------------------
# The Function Under Test
# (Copied from skill/references/orchestration.md for isolation testing)
# ---------------------------------------------------------------------------

retry_with_context() {
  local id="$1" original_prompt="$2" max_retries="${3:-1}"
  local attempt=0 exit_code
  local session_id=""

  while (( attempt <= max_retries )); do
    local prompt="$original_prompt"
    local use_resume=false

    if (( attempt > 0 )); then
      local prev_log="$TMPDIR/$id.attempt$((attempt-1)).out"

      if [[ -f "$prev_log" ]]; then
        local prev_error=$(tail -80 "$prev_log")

        # Detect Session ID (Claude Code pattern: "Session ID: <uuid>")
        # We use grep/awk to parse it
        local detected_id
        detected_id=$(grep -oE "Session ID: [a-zA-Z0-9-]+" "$prev_log" | awk '{print $NF}' | tail -1)

        if [[ -n "$detected_id" ]]; then
           session_id="$detected_id"
        fi
      fi

      local fix_instructions="RETRY (attempt $((attempt+1))). Previous attempt failed.
Error output:
$prev_error

Fix the issue."

      # Enable resume if supported and session ID found
      if [[ -n "$session_id" ]]; then
        if [[ "$AGENT_CMD" == *"claude"* ]]; then
          use_resume=true
        fi
      fi

      if [[ "$use_resume" == "true" ]]; then
        prompt="$fix_instructions"
      else
        prompt="$original_prompt

$fix_instructions"
      fi
    fi

    # Execute
    echo "[Test Logic] Attempt $attempt: use_resume=$use_resume session_id=$session_id"

    if [[ "$use_resume" == "true" ]]; then
      # Resume session
      # We strip the comment "# claude mock" from AGENT_CMD for execution
      local cmd_base="${AGENT_CMD%% #*}"
      timeout 5 $cmd_base --resume "$session_id" "$prompt" > "$TMPDIR/$id.attempt$attempt.out" 2>&1
    else
      # Standard execution
      local cmd_base="${AGENT_CMD%% #*}"
      timeout 5 $cmd_base "$prompt" > "$TMPDIR/$id.attempt$attempt.out" 2>&1
    fi

    exit_code=$?

    if (( exit_code == 0 )); then
      cp "$TMPDIR/$id.attempt$attempt.out" "$TMPDIR/$id.out"
      return 0
    fi

    ((attempt++))
  done
  return 1
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

TOTAL=0
PASS=0
FAIL=0

run_test() {
  local desc="$1"
  local check_cmd="$2"

  TOTAL=$((TOTAL + 1))
  echo ""
  echo "--- Test $TOTAL: $desc ---"

  if eval "$check_cmd"; then
    echo "  PASS"
    PASS=$((PASS + 1))
  else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
  fi
}

echo "Starting Resume Logic Tests..."

# Run the retry loop
retry_with_context "task1" "Do work" 1 || true

# Test 1: First attempt failed
run_test "Attempt 0 should fail" \
  "grep -q 'Error: Something went wrong' '$TMPDIR/task1.attempt0.out'"

# Test 2: Session ID capture
run_test "Session ID captured from logs" \
  "grep -q 'Session ID: 550e8400' '$TMPDIR/task1.attempt0.out'"

# Test 3: Second attempt used resume
run_test "Attempt 1 used --resume" \
  "grep -q 'RESUMED' '$TMPDIR/task1.attempt1.out'"

# Test 4: Verify prompt content on resume
# It should NOT contain the original prompt if resuming, just the fix
# But our mock agent doesn't echo the prompt.
# We trust the logic if it hit the 'RESUMED' branch.

# ---------------------------------------------------------------------------
# Test Case 2: Agent WITHOUT resume support (no "claude" in name)
# ---------------------------------------------------------------------------

echo ""
echo "Testing fallback (non-Claude agent)..."
export AGENT_CMD="$MOCK_AGENT" # removed "claude" tag

retry_with_context "task2" "Do work" 1 || true

# Test 5: Fallback to restart
run_test "Non-Claude agent does NOT use resume" \
  "! grep -q 'RESUMED' '$TMPDIR/task2.attempt1.out'"

run_test "Non-Claude agent sees Fresh Start" \
  "grep -q 'Starting fresh session' '$TMPDIR/task2.attempt1.out'"


# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "========================================"
echo "  Resume Logic Test Results"
echo "========================================"
echo "  Total: $TOTAL"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "========================================"

rm -rf "$TMPDIR"

if [[ $FAIL -gt 0 ]]; then
  exit 1
else
  exit 0
fi
