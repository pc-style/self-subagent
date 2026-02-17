#!/usr/bin/env bash
# Aggregate scorecard generator
set -euo pipefail

RESULTS_DIR="$1"

echo "Generating scorecard..."

DISCOVERY=$(cat "$RESULTS_DIR/score_discovery" 2>/dev/null || echo "0")
CORRECTNESS=$(cat "$RESULTS_DIR/score_correctness" 2>/dev/null || echo "0")
PARALLELISM=$(cat "$RESULTS_DIR/score_parallelism" 2>/dev/null || echo "0")

OVERALL=$(( (DISCOVERY + CORRECTNESS + PARALLELISM) / 3 ))

cat > "$RESULTS_DIR/scorecard.txt" << EOF
╔════════════════════════════════════════════════════════╗
║              TEST HARNESS SCORECARD                    ║
╠════════════════════════════════════════════════════════╣
║  Discovery:    $DISCOVERY/10  $(printf '%*s' $((10-DISCOVERY)) '' | tr ' ' '▒')║
║  Correctness:  $CORRECTNESS/10  $(printf '%*s' $((10-CORRECTNESS)) '' | tr ' ' '▒')║
║  Parallelism:  $PARALLELISM/10  $(printf '%*s' $((10-PARALLELISM)) '' | tr ' ' '▒')║
╠════════════════════════════════════════════════════════╣
║  OVERALL:      $OVERALL/10  $(printf '%*s' $((10-OVERALL)) '' | tr ' ' '█')║
╚════════════════════════════════════════════════════════╝

Discovery:    Did it modify the expected files?
Correctness:  Does the code pass validation?
Parallelism:  Did it use concurrent execution?
EOF

echo "Scorecard saved to: $RESULTS_DIR/scorecard.txt"