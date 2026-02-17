#!/usr/bin/env bash
# Score parallelism efficiency - did it use concurrency effectively?
set -euo pipefail

RESULTS_DIR="$1"
NUM_TASKS="${2:-5}"

DURATION=$(cat "$RESULTS_DIR/duration" 2>/dev/null || echo "0")

# Sequential estimate: 2 minutes per task
SEQUENTIAL_ESTIMATE=$((NUM_TASKS * 120))

# If duration is 0 or too short, parallelism couldn't be measured
if [[ $DURATION -lt 30 ]]; then
  echo "Duration too short to measure parallelism ($DURATION s)"
  echo "3" > "$RESULTS_DIR/score_parallelism"
  
  cat > "$RESULTS_DIR/parallelism_report.txt" << EOF
Parallelism Scoring Report
==========================
Score: 3/10 (could not measure)

Duration: ${DURATION}s
Sequential estimate: ${SEQUENTIAL_ESTIMATE}s
Speedup: N/A

Note: Test completed too quickly to measure parallelism effectively.
This could mean:
- Tasks were run sequentially but very fast
- The subagent didn't actually spawn parallel workers
- There was an error early in execution
EOF
  exit 0
fi

# Calculate speedup
if [[ $DURATION -gt 0 ]]; then
  SPEEDUP=$(echo "scale=2; $SEQUENTIAL_ESTIMATE / $DURATION" | bc 2>/dev/null || echo "1")
else
  SPEEDUP=1
fi

# Score based on speedup
# 5-6x = perfect parallelization (5+ tasks running concurrently)
# 4-5x = good parallelization
# 3-4x = moderate
# 2-3x = limited
# <2x = mostly sequential

SCORE=5
if (( $(echo "$SPEEDUP >= 5" | bc -l) )); then
  SCORE=10
elif (( $(echo "$SPEEDUP >= 4" | bc -l) )); then
  SCORE=9
elif (( $(echo "$SPEEDUP >= 3.5" | bc -l) )); then
  SCORE=8
elif (( $(echo "$SPEEDUP >= 3" | bc -l) )); then
  SCORE=7
elif (( $(echo "$SPEEDUP >= 2.5" | bc -l) )); then
  SCORE=6
elif (( $(echo "$SPEEDUP >= 2" | bc -l) )); then
  SCORE=5
elif (( $(echo "$SPEEDUP >= 1.5" | bc -l) )); then
  SCORE=3
else
  SCORE=2
fi

echo "Parallelism Score: $SCORE/10"
echo "Speedup: ${SPEEDUP}x (sequential: ${SEQUENTIAL_ESTIMATE}s, actual: ${DURATION}s)"
echo "$SCORE" > "$RESULTS_DIR/score_parallelism"

# Save report
cat > "$RESULTS_DIR/parallelism_report.txt" << EOF
Parallelism Scoring Report
==========================
Score: $SCORE/10

Duration: ${DURATION}s
Sequential estimate: ${SEQUENTIAL_ESTIMATE}s  
Speedup: ${SPEEDUP}x

Interpretation:
- 5-6x speedup: Perfect parallelization (all tasks ran concurrently)
- 4-5x speedup: Good parallelization (4-5 tasks concurrent)
- 3-4x speedup: Moderate parallelization (3 tasks concurrent)
- 2-3x speedup: Limited parallelization (2 tasks concurrent)
- <2x speedup: Mostly sequential execution
EOF

exit 0