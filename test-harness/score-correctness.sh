#!/usr/bin/env bash
# Score output correctness - does it pass validation?
set -euo pipefail

REPO_DIR="$1"
RESULTS_DIR="$2"

cd "$REPO_DIR"

SCORE=10
ERRORS=""

# Check TypeScript compilation
echo "Checking TypeScript compilation..."
if ! npx tsc --noEmit 2>&1; then
  SCORE=$((SCORE - 4))
  ERRORS="${ERRORS}TypeScript compilation failed\n"
  echo "FAIL: TypeScript compilation"
else
  echo "PASS: TypeScript compilation"
fi

# Check for secrets/credentials in the code
echo "Checking for secrets..."
if grep -r -E "(api[_-]?key|apikey|secret|token|password)\s*[=:]\s*[\"'][^\"']+[\"']" src/ 2>/dev/null | grep -v "process\.env" | head -5; then
  SCORE=$((SCORE - 3))
  ERRORS="${ERRORS}Potential secrets found in code\n"
  echo "WARNING: Potential secrets found"
else
  echo "PASS: No obvious secrets found"
fi

# Check for basic error handling patterns
echo "Checking for error handling patterns..."
ERROR_PATTERNS=0
for file in src/*.ts; do
  if grep -q 'try\|catch\|Error\|throw' "$file" 2>/dev/null; then
    ERROR_PATTERNS=$((ERROR_PATTERNS + 1))
  fi
done

if [[ $ERROR_PATTERNS -lt 3 ]]; then
  SCORE=$((SCORE - 2))
  ERRORS="${ERRORS}Insufficient error handling patterns found\n"
  echo "WARNING: Only $ERROR_PATTERNS files have error handling"
else
  echo "PASS: Error handling found in $ERROR_PATTERNS files"
fi

# Check for custom error classes
echo "Checking for custom error classes..."
if grep -r 'class.*Error.*extends' src/ 2>/dev/null | head -3; then
  echo "PASS: Custom error classes found"
else
  SCORE=$((SCORE - 1))
  ERRORS="${ERRORS}No custom error classes found\n"
  echo "WARNING: No custom error classes"
fi

# Clamp score
if [[ $SCORE -lt 0 ]]; then SCORE=0; fi
if [[ $SCORE -gt 10 ]]; then SCORE=10; fi

echo "Correctness Score: $SCORE/10"
echo "$SCORE" > "$RESULTS_DIR/score_correctness"

# Save report
cat > "$RESULTS_DIR/correctness_report.txt" << EOF
Correctness Scoring Report
==========================
Score: $SCORE/10

Checks performed:
- TypeScript compilation
- Secret/credential scan
- Error handling patterns
- Custom error classes

Errors:
${ERRORS:-None}
EOF

exit 0