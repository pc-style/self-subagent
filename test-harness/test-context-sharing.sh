#!/usr/bin/env bash
# Test: Context Sharing (Upgrade #8)
# Verifies that context-packer.sh correctly aggregates files and they are readable.
#
# Usage: ./test-harness/test-context-sharing.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKER="$PROJECT_DIR/skill/context-packer.sh"

export TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

PASS_COUNT=0
FAIL_COUNT=0
TOTAL=0

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

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

echo "Creating dummy files..."
mkdir -p "$TMPDIR/src" "$TMPDIR/docs"

cat > "$TMPDIR/src/types.ts" << 'EOF'
export interface User {
  id: string;
  name: string;
  email: string;
}
EOF

cat > "$TMPDIR/docs/guidelines.md" << 'EOF'
# Coding Guidelines
1. Use strict types.
2. No any.
EOF

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

OUTPUT_FILE="$TMPDIR/shared-context.md"

# Test 1: Pack files
run_test "Pack context files" \
  "'$PACKER' '$OUTPUT_FILE' '$TMPDIR/src/types.ts' '$TMPDIR/docs/guidelines.md'"

# Test 2: Verify file existence
run_test "Output file exists" \
  "[[ -f '$OUTPUT_FILE' ]]"

# Test 3: Verify content - Header
run_test "Contains header" \
  "grep -q '# Shared Context' '$OUTPUT_FILE'"

# Test 4: Verify content - File 1
run_test "Contains types.ts content" \
  "grep -q 'export interface User' '$OUTPUT_FILE'"

# Test 5: Verify content - File 2
run_test "Contains guidelines.md content" \
  "grep -q 'No any' '$OUTPUT_FILE'"

# Test 6: Verify file path labels
run_test "Contains file path labels" \
  "grep -q '## File: .*src/types.ts' '$OUTPUT_FILE'"

# Test 7: Mock Subagent Read Access
# Simulate a subagent that is told to read the file
# Ideally, subagents just 'cat' or read the file.
run_test "Simulate subagent read" \
  "cat '$OUTPUT_FILE' >/dev/null"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "========================================"
echo "  Context Sharing Test Results"
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
