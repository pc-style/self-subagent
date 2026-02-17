#!/usr/bin/env bash
# Score discovery accuracy - did the subagent modify the right files?
set -euo pipefail

REPO_DIR="$1"
SCENARIO="${2:-01-error-handling}"
RESULTS_DIR="$3"

EXPECTED_FILES=("src/auth.ts" "src/payments.ts" "src/user.ts" "src/utils.ts" "src/api.ts")

cd "$REPO_DIR"

# Get list of modified files
MODIFIED_FILES=$(git diff --name-only 2>/dev/null | sort || echo "")

echo "Expected files: ${EXPECTED_FILES[*]}"
echo "Modified files: $MODIFIED_FILES"

# Calculate discovery score
SCORE=10
MISSING=0
UNEXPECTED=0

for expected in "${EXPECTED_FILES[@]}"; do
  if ! echo "$MODIFIED_FILES" | grep -q "^$expected$"; then
    MISSING=$((MISSING + 1))
    echo "MISSING: $expected"
  fi
done

# Check for unexpected files
for modified in $MODIFIED_FILES; do
  if [[ "$modified" == src/*.ts ]]; then
    if ! [[ " ${EXPECTED_FILES[*]} " =~ " ${modified} " ]]; then
      UNEXPECTED=$((UNEXPECTED + 1))
      echo "UNEXPECTED: $modified"
    fi
  fi
done

# Calculate score
# -2 points for each missing expected file
# -1 point for each unexpected file
SCORE=$((SCORE - MISSING * 2 - UNEXPECTED))

# Clamp to 0-10
if [[ $SCORE -lt 0 ]]; then SCORE=0; fi
if [[ $SCORE -gt 10 ]]; then SCORE=10; fi

echo "Discovery Score: $SCORE/10"
echo "$SCORE" > "$RESULTS_DIR/score_discovery"

# Save details
cat > "$RESULTS_DIR/discovery_report.txt" << EOF
Discovery Scoring Report
========================
Expected files: ${#EXPECTED_FILES[@]}
Modified files: $(echo "$MODIFIED_FILES" | wc -l)
Missing expected: $MISSING
Unexpected files: $UNEXPECTED

Score: $SCORE/10

Expected:
$(printf '  - %s\n' "${EXPECTED_FILES[@]}")

Modified:
$(printf '  - %s\n' $MODIFIED_FILES)
EOF

exit 0