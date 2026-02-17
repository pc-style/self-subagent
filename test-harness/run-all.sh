#!/usr/bin/env bash
# Main test harness - runs all available CLIs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCENARIO="${1:-01-error-handling}"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║        SELF-SUBAGENT REAL-WORLD TEST HARNESS             ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Scenario: $SCENARIO"
echo "Started at: $(date)"
echo ""

# Check which CLIs are available
AVAILABLE_CLIS=()

if command -v claude &>/dev/null; then
  AVAILABLE_CLIS+=("claude")
  echo "✓ Claude Code found"
fi

if command -v codex &>/dev/null; then
  AVAILABLE_CLIS+=("codex")
  echo "✓ Codex CLI found"
fi

if command -v amp &>/dev/null; then
  AVAILABLE_CLIS+=("amp")
  echo "✓ Amp CLI found"
fi

if command -v aider &>/dev/null; then
  AVAILABLE_CLIS+=("aider")
  echo "✓ aider found"
fi

if [[ ${#AVAILABLE_CLIS[@]} -eq 0 ]]; then
  echo "ERROR: No supported CLIs found!"
  echo ""
  echo "Supported CLIs: claude, codex, amp, aider"
  echo ""
  echo "To run a specific CLI manually:"
  echo "  ./test-harness/runners/run-claude.sh"
  echo "  ./test-harness/runners/run-codex.sh"
  echo "  ./test-harness/runners/run-amp.sh"
  echo "  ./test-harness/runners/run-aider.sh"
  exit 1
fi

echo ""
echo "Will run tests against: ${AVAILABLE_CLIS[*]}"
echo ""

# Run tests for each CLI
for cli in "${AVAILABLE_CLIS[@]}"; do
  echo "=========================================="
  echo "Running test for: $cli"
  echo "=========================================="
  echo ""
  
  "$SCRIPT_DIR/runners/run-$cli.sh" "$SCENARIO"
  
  echo ""
  echo "Completed: $cli"
  echo ""
done

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                   ALL TESTS COMPLETE                     ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Generate aggregate report
echo "Aggregate Results:"
echo ""

for cli in "${AVAILABLE_CLIS[@]}"; do
  # Find the most recent result for this CLI
  LATEST_RESULT=$(ls -td "$SCRIPT_DIR/results/$cli-"* 2>/dev/null | head -1 || echo "")
  if [[ -n "$LATEST_RESULT" && -f "$LATEST_RESULT/scorecard.txt" ]]; then
    echo "--- $cli ---"
    cat "$LATEST_RESULT/scorecard.txt"
    echo ""
  fi
done

echo ""
echo "Full results available in: $SCRIPT_DIR/results/"
echo ""
echo "Completed at: $(date)"