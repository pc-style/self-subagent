#!/usr/bin/env bash
# Test: Cost Tracker (Upgrade #2)
# Verifies that cost-tracker.sh correctly calculates costs and enforces budgets.
#
# Usage: ./test-harness/test-cost-tracker.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TRACKER="$PROJECT_DIR/skill/cost-tracker.sh"

# Mock config
export COST_FILE="$(mktemp)"
export BUDGET_LIMIT="0.10" # Set a low budget for testing ($0.10)

PASS_COUNT=0
FAIL_COUNT=0
TOTAL=0

# Clean up on exit
trap "rm -f $COST_FILE" EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

run_test() {
  local name="$1"
  local cmd="$2"

  TOTAL=$((TOTAL + 1))
  echo ""
  echo "--- Test $TOTAL: $name ---"

  if eval "$cmd"; then
    echo "  PASS"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  FAIL"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

assert_cost_file_contains() {
  local pattern="$1"
  if grep -q "$pattern" "$COST_FILE"; then
    return 0
  else
    echo "    Expected pattern '$pattern' not found in cost file:"
    cat "$COST_FILE" | sed 's/^/      /'
    return 1
  fi
}

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  if [[ "$expected" == "$actual" ]]; then
    return 0
  else
    echo "    Expected exit code $expected, got $actual"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

echo "Testing Cost Tracker..."
echo "Tracker: $TRACKER"
echo "Cost File: $COST_FILE"
echo "Budget Limit: $BUDGET_LIMIT"

# Test 1: Track usage (Sonnet)
# Sonnet pricing (approx): Input $3.00/1M, Output $15.00/1M
# 1000 in, 1000 out -> (0.003 + 0.015) / 1000 * 1000 = $0.018
run_test "Track usage (Sonnet)" \
  "'$TRACKER' track 'claude-3-5-sonnet' 1000 1000 'task-1'"

run_test "Verify cost calculation (Sonnet)" \
  "assert_cost_file_contains ':0.018000'"

# Test 2: Check budget (should pass)
# Current total: $0.018, Limit: $0.10
run_test "Check budget (under limit)" \
  "'$TRACKER' check >/dev/null"

# Test 3: Track usage (Opus) to near limit
# Opus pricing: Input $15.00/1M, Output $75.00/1M
# 1000 in, 1000 out -> (0.015 + 0.075) / 1000 * 1000 = $0.090
run_test "Track usage (Opus)" \
  "'$TRACKER' track 'claude-3-opus' 1000 1000 'task-2'"

run_test "Verify cost calculation (Opus)" \
  "assert_cost_file_contains ':0.090000'"

# Total is now 0.018 + 0.090 = 0.108
# Limit is 0.10

# Test 4: Check budget (should fail)
echo ""
echo "--- Test $((TOTAL + 1)): Check budget (over limit) ---"
TOTAL=$((TOTAL + 1))
EXIT_CODE=0
"$TRACKER" check >/dev/null 2>&1 || EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 ]]; then
  echo "  PASS (Budget exceeded check returned non-zero)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "  FAIL (Expected non-zero exit code for budget overrun)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Test 5: Report generation
run_test "Generate report" \
  "'$TRACKER' report | grep -q 'TOTAL'"

echo ""
echo "Report Output:"
"$TRACKER" report | sed 's/^/  /'

# Test 6: Unknown model fallback
# Should fall back to Sonnet pricing ($3/$15)
# 1M in, 0 out -> $3.00
run_test "Unknown model fallback" \
  "'$TRACKER' track 'unknown-model' 1000000 0 'task-3'"

run_test "Verify fallback cost" \
  "assert_cost_file_contains ':3.000000'"

# Test 7: Clear log
run_test "Clear log" \
  "'$TRACKER' clear && [[ ! -s $COST_FILE ]]"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "========================================"
echo "  Cost Tracker Test Results"
echo "========================================"
echo "  Total: $TOTAL"
echo "  Passed: $PASS_COUNT"
echo "  Failed: $FAIL_COUNT"
echo "========================================"

if [[ $FAIL_COUNT -gt 0 ]]; then
  exit 1
else
  exit 0
fi
