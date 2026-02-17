#!/usr/bin/env bash
# Quick test script to verify the harness works
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║     SELF-SUBAGENT TEST HARNESS - QUICK TEST              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check which CLIs are available
echo "Checking available CLIs..."
echo ""

FOUND=0

if command -v claude &>/dev/null; then
  echo "✓ Claude Code found"
  FOUND=$((FOUND + 1))
fi

if command -v codex &>/dev/null; then
  echo "✓ Codex CLI found"
  FOUND=$((FOUND + 1))
fi

if command -v amp &>/dev/null; then
  echo "✓ Amp CLI found"
  FOUND=$((FOUND + 1))
fi

if command -v aider &>/dev/null; then
  echo "✓ aider found"
  FOUND=$((FOUND + 1))
fi

echo ""

if [[ $FOUND -eq 0 ]]; then
  echo "⚠ No CLIs found. To run the test harness, install one of:"
  echo "  - Claude Code: npm install -g @anthropic-ai/claude-code"
  echo "  - Codex CLI: npm install -g @openai/codex"
  echo "  - Amp: https://amp.dev"
  echo "  - aider: pip install aider-chat"
  echo ""
  echo "Then run: ./test-harness/run-all.sh"
  exit 1
fi

echo "Found $FOUND CLI(s) available for testing"
echo ""

# Show what will be tested
echo "Test configuration:"
echo "  Sample repo: $SCRIPT_DIR/sample-repo/"
echo "  Scenario: 01-error-handling"
echo "  Expected files to modify: 5"
echo "    - src/auth.ts"
echo "    - src/payments.ts"
echo "    - src/user.ts"
echo "    - src/utils.ts"
echo "    - src/api.ts"
echo ""

# Verify sample repo compiles
echo "Verifying sample repo..."
cd "$SCRIPT_DIR/sample-repo"
if /Users/pcstyle/projects/self-subagent/test-harness/sample-repo/node_modules/.bin/tsc -p tsconfig.json --noEmit 2>&1; then
  echo "✓ TypeScript compiles"
else
  echo "✗ TypeScript compilation failed"
  exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                    READY TO TEST                         ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "To run the full test harness:"
echo "  ./test-harness/run-all.sh"
echo ""
echo "To test a specific CLI:"
echo "  ./test-harness/runners/run-claude.sh"
echo "  ./test-harness/runners/run-codex.sh"
echo "  ./test-harness/runners/run-amp.sh"
echo "  ./test-harness/runners/run-aider.sh"
echo ""
echo "NOTE: Each test takes 5-10 minutes and costs API tokens!"
echo ""

exit 0