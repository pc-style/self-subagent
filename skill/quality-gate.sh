#!/usr/bin/env bash
# Quality Gate - Score subagent output before merging
# Usage: quality-gate.sh <subagent_dir> <results_dir> <expected_files> [task_complexity]
#
# Exit codes:
#   0 = ACCEPT (score >= 6, diff clean)
#   1 = REJECT (score < 6 or diff verification failed)
#   2 = SECRETS_FOUND (hard block — auto-reverted)

set -euo pipefail

SUBAGENT_DIR="${1:-}"
RESULTS_DIR="${2:-}"
EXPECTED_FILES="${3:-}"
TASK_COMPLEXITY="${4:-medium}"

# Resolve path to diff-verify.sh (same directory as this script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIFF_VERIFY="$SCRIPT_DIR/diff-verify.sh"

if [[ -z "$SUBAGENT_DIR" || -z "$RESULTS_DIR" || -z "$EXPECTED_FILES" ]]; then
  echo "Usage: $0 <subagent_dir> <results_dir> <expected_files> [task_complexity]"
  echo "  expected_files: space-separated list of files the subagent should modify"
  echo "  task_complexity: small|medium|large (default: medium)"
  echo ""
  echo "Exit codes: 0=ACCEPT, 1=REJECT, 2=SECRETS_FOUND"
  exit 1
fi

mkdir -p "$RESULTS_DIR"

# ---------------------------------------------------------------------------
# Phase 0: Diff-Based Verification (pre-check)
# Run secret scan, rogue edit detection, and diff proportionality BEFORE
# doing any expensive validation (typecheck, lint, tests).
# ---------------------------------------------------------------------------
echo "╔════════════════════════════════════════════════════╗"
echo "║  Phase 0: Diff-Based Verification                 ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

if [[ -x "$DIFF_VERIFY" ]]; then
  DIFF_EXIT=0
  "$DIFF_VERIFY" "$SUBAGENT_DIR" "$RESULTS_DIR" "$EXPECTED_FILES" "$TASK_COMPLEXITY" || DIFF_EXIT=$?

  if [[ $DIFF_EXIT -eq 2 ]]; then
    # Secrets found — hard block, diff-verify already auto-reverted
    echo ""
    echo "╔════════════════════════════════════════════════════╗"
    echo "║     QUALITY GATE: BLOCKED (SECRETS DETECTED)       ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo ""
    echo "Changes have been auto-reverted."
    echo "0" > "$RESULTS_DIR/quality_score"
    cat > "$RESULTS_DIR/quality_report.txt" << EOF
Quality Gate Report
===================
Score: 0/10
Status: BLOCKED — secrets detected in diff
Changes were auto-reverted.
See: $RESULTS_DIR/diff_verify_report.txt
EOF
    exit 2
  elif [[ $DIFF_EXIT -eq 1 ]]; then
    echo ""
    echo "Diff verification failed (rogue edits or oversized diff)."
    echo "Changes have been auto-reverted."
    echo "Skipping expensive validation."
    echo ""
    echo "╔════════════════════════════════════════════════════╗"
    echo "║     QUALITY GATE: 0/10 (DIFF VERIFICATION FAILED)  ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo ""
    echo "0" > "$RESULTS_DIR/quality_score"
    cat > "$RESULTS_DIR/quality_report.txt" << EOF
Quality Gate Report
===================
Score: 0/10
Status: REJECTED — diff verification failed
Changes were auto-reverted.
See: $RESULTS_DIR/diff_verify_report.txt
EOF
    exit 1
  else
    echo ""
    echo "Diff verification PASSED. Proceeding to quality scoring..."
    echo ""
  fi
else
  echo "WARNING: diff-verify.sh not found at $DIFF_VERIFY — skipping diff verification"
  echo ""
fi

# ---------------------------------------------------------------------------
# Phase 1: Quality Scoring
# ---------------------------------------------------------------------------
echo "╔════════════════════════════════════════════════════╗"
echo "║  Phase 1: Quality Scoring                         ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

cd "$SUBAGENT_DIR"

SCORE=10
FAILURES=""
UNEXPECTED=0
MISSING=0
VALIDATION_FAILED=0

echo "Running Quality Gate..."
echo "Directory: $SUBAGENT_DIR"
echo "Expected files: $EXPECTED_FILES"
echo ""

# 1. File Scope Check (4 points)
echo "→ Checking file scope..."
MODIFIED=$(git diff --name-only 2>/dev/null | sort || echo "")

if [[ -z "$MODIFIED" ]]; then
  echo "⚠️  No files modified"
  SCORE=$((SCORE - 4))
  FAILURES="${FAILURES}No files modified\n"
else
  for file in $MODIFIED; do
    if [[ ! " $EXPECTED_FILES " =~ " $file " ]]; then
      UNEXPECTED=$((UNEXPECTED + 1))
      FAILURES="${FAILURES}UNEXPECTED: $file\n"
    fi
  done

  for expected in $EXPECTED_FILES; do
    if ! echo "$MODIFIED" | grep -q "^$expected$"; then
      MISSING=$((MISSING + 1))
      FAILURES="${FAILURES}MISSING: $expected\n"
    fi
  done

  if [[ $UNEXPECTED -gt 0 || $MISSING -gt 0 ]]; then
    SCORE=$((SCORE - 4))
    echo "⚠️  File scope violation: $UNEXPECTED unexpected, $MISSING missing"
  else
    echo "✓ File scope: PASS (all expected files modified, no extras)"
  fi
fi

# 2. Validation Check (4 points)
echo ""
echo "→ Running validation checks..."

# TypeScript - use absolute path to avoid npx issues
if [[ -f "tsconfig.json" ]]; then
  if [[ -f "./node_modules/.bin/tsc" ]]; then
    if ! ./node_modules/.bin/tsc --noEmit 2>&1 | head -20; then
      SCORE=$((SCORE - 2))
      VALIDATION_FAILED=1
      FAILURES="${FAILURES}TypeScript compilation failed\n"
      echo "❌ TypeScript compilation failed"
    else
      echo "✓ TypeScript: PASS"
    fi
  elif command -v npx >/dev/null 2>&1; then
    if ! npx tsc --noEmit 2>&1 | head -20; then
      SCORE=$((SCORE - 2))
      VALIDATION_FAILED=1
      FAILURES="${FAILURES}TypeScript compilation failed\n"
      echo "❌ TypeScript compilation failed"
    else
      echo "✓ TypeScript: PASS"
    fi
  fi
fi

# Lint
if [[ -f "package.json" ]] && grep -q '"lint"' package.json 2>/dev/null; then
  if ! npm run lint 2>&1 | tail -10; then
    SCORE=$((SCORE - 1))
    VALIDATION_FAILED=1
    FAILURES="${FAILURES}Lint failed\n"
    echo "❌ Lint failed"
  else
    echo "✓ Lint: PASS"
  fi
fi

# Tests
if [[ -f "package.json" ]] && grep -q '"test"' package.json 2>/dev/null; then
  if ! npm test 2>&1 | tail -10; then
    SCORE=$((SCORE - 1))
    VALIDATION_FAILED=1
    FAILURES="${FAILURES}Tests failed\n"
    echo "❌ Tests failed"
  else
    echo "✓ Tests: PASS"
  fi
fi

# 3. Diff Size Check (2 points)
echo ""
echo "→ Checking diff size..."
DIFF_LINES=$(git diff --stat 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")

# Thresholds by complexity
if [[ "$TASK_COMPLEXITY" == "small" ]]; then
  MAX_LINES=50
elif [[ "$TASK_COMPLEXITY" == "large" ]]; then
  MAX_LINES=500
else
  MAX_LINES=200  # medium
fi

if [[ $DIFF_LINES -gt $MAX_LINES ]]; then
  SCORE=$((SCORE - 2))
  FAILURES="${FAILURES}Diff too large: $DIFF_LINES lines (max $MAX_LINES for $TASK_COMPLEXITY task)\n"
  echo "⚠️  Diff size: $DIFF_LINES lines exceeds threshold ($MAX_LINES)"
else
  echo "✓ Diff size: $DIFF_LINES lines (threshold: $MAX_LINES)"
fi

# Clamp to 0-10
[[ $SCORE -lt 0 ]] && SCORE=0
[[ $SCORE -gt 10 ]] && SCORE=10

# Save results
echo "$SCORE" > "$RESULTS_DIR/quality_score"

# Include diff verification status if available
DIFF_STATUS="N/A (not run)"
if [[ -f "$RESULTS_DIR/diff_verify_status" ]]; then
  DIFF_STATUS=$(cat "$RESULTS_DIR/diff_verify_status")
fi

cat > "$RESULTS_DIR/quality_report.txt" << EOF
Quality Gate Report
===================
Score: $SCORE/10

Phase 0 - Diff Verification: $DIFF_STATUS

Phase 1 - Quality Scoring:
- File Scope: $([[ $UNEXPECTED -eq 0 && $MISSING -eq 0 ]] && echo "PASS" || echo "FAIL") ($UNEXPECTED unexpected, $MISSING missing)
- Validation: $([[ $VALIDATION_FAILED -eq 0 ]] && echo "PASS" || echo "FAIL")
- Diff Size: $DIFF_LINES lines $([[ $DIFF_LINES -le $MAX_LINES ]] && echo "(PASS)" || echo "(FAIL - max $MAX_LINES)")

Failures:
${FAILURES:-None}

Modified Files:
$(git diff --name-only 2>/dev/null || echo "N/A")

Git Diff Stats:
$(git diff --stat 2>/dev/null || echo "N/A")
EOF

# Output result
echo ""
echo "╔════════════════════════════════════════════════════╗"
printf "║     QUALITY GATE: %d/10                            ║\n" "$SCORE"
echo "╚════════════════════════════════════════════════════╝"
echo ""

if [[ $SCORE -ge 6 ]]; then
  echo "ACCEPT: Changes meet quality threshold (>=6/10)"
  echo ""
  echo "Breakdown:"
  echo "  Phase 0 (Diff Verify): $DIFF_STATUS"
  [[ $UNEXPECTED -eq 0 && $MISSING -eq 0 ]] && echo "  Phase 1 File scope: 4/4 points" || echo "  Phase 1 File scope: 0/4 points"
  [[ $VALIDATION_FAILED -eq 0 ]] && echo "  Phase 1 Validation: 4/4 points" || echo "  Phase 1 Validation: reduced"
  [[ $DIFF_LINES -le $MAX_LINES ]] && echo "  Phase 1 Diff size: 2/2 points" || echo "  Phase 1 Diff size: 0/2 points"
  exit 0
else
  echo "REJECT: Changes below quality threshold (<6/10)"
  echo ""
  echo "Recommended actions:"
  echo "  1. Retry subagent with error context appended to prompt"
  echo "  2. Do task inline (parent agent handles it)"
  exit 1
fi
