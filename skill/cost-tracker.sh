#!/usr/bin/env bash
# Cost Tracker for Self-Subagent Skill
# Tracks token usage and estimates costs to prevent budget overruns.
# Avoids associative arrays for maximum compatibility.
#
# Usage:
#   source cost-tracker.sh
#   track_usage "claude-3-sonnet" 1000 500 "task-123"
#   check_budget
#
# Or run directly:
#   ./cost-tracker.sh track "claude-3-sonnet" 1000 500 "task-123"
#   ./cost-tracker.sh check
#   ./cost-tracker.sh report

set -euo pipefail

# Configuration
COST_FILE="${COST_FILE:-/tmp/subagent-costs.log}"
BUDGET_LIMIT="${BUDGET_LIMIT:-5.00}"  # Default $5.00 limit

# normalize_model <model_name>
# Returns a standardized model key
normalize_model() {
  local model="$1"
  case "$model" in
    *haiku*)       echo "haiku" ;;
    *sonnet*)      echo "sonnet" ;;
    *opus*)        echo "opus" ;;
    *gpt-4o-mini*) echo "gpt-4o-mini" ;;
    *gpt-4o*)      echo "gpt-4o" ;;
    *gpt-4*)       echo "gpt-4-turbo" ;;
    *gpt-3.5*)     echo "gpt-3.5-turbo" ;;
    *)             echo "sonnet" ;; # Default fallback
  esac
}

# get_pricing <normalized_model>
# Outputs: input_price_per_1m output_price_per_1m
# Pricing as of mid-2024 (approximate)
get_pricing() {
  local model="$1"
  case "$model" in
    haiku)         echo "0.25 1.25" ;;
    sonnet)        echo "3.00 15.00" ;;
    opus)          echo "15.00 75.00" ;;
    gpt-4o)        echo "2.50 10.00" ;;
    gpt-4o-mini)   echo "0.15 0.60" ;;
    gpt-4-turbo)   echo "10.00 30.00" ;;
    gpt-3.5-turbo) echo "0.50 1.50" ;;
    *)             echo "3.00 15.00" ;; # Default to Sonnet pricing
  esac
}

# calculate_cost <model> <input_tokens> <output_tokens>
calculate_cost() {
  local model
  model=$(normalize_model "$1")
  local input_toks="${2:-0}"
  local output_toks="${3:-0}"

  # Get pricing
  local prices
  prices=$(get_pricing "$model")
  local p_in
  local p_out
  p_in=$(echo "$prices" | awk '{print $1}')
  p_out=$(echo "$prices" | awk '{print $2}')

  # Cost = (input * p_in + output * p_out) / 1,000,000
  # Using awk for floating point math
  awk -v i="$input_toks" -v o="$output_toks" -v pi="$p_in" -v po="$p_out" \
    'BEGIN { printf "%.6f", (i * pi / 1000000) + (o * po / 1000000) }'
}

# track_usage <model> <input> <output> [task_id]
track_usage() {
  local model="$1"
  local input_toks="${2:-0}"
  local output_toks="${3:-0}"
  local task_id="${4:-unknown}"

  if [[ -z "$model" ]]; then
    echo "Usage: track_usage <model> <input_tokens> <output_tokens> [task_id]"
    return 1
  fi

  local cost
  cost=$(calculate_cost "$model" "$input_toks" "$output_toks")

  # Log format: timestamp:task_id:model:input:output:cost
  echo "$(date +%s):$task_id:$model:$input_toks:$output_toks:$cost" >> "$COST_FILE"
}

# check_budget [limit]
# Returns 0 if under budget, 1 if over
check_budget() {
  local current_limit="${1:-$BUDGET_LIMIT}"

  if [[ ! -f "$COST_FILE" ]]; then
    echo "0.00"
    return 0
  fi

  local total_cost
  total_cost=$(awk -F: '{sum+=$6} END {printf "%.4f", sum}' "$COST_FILE")

  # Use awk for float comparison to avoid bc dependency
  local is_over
  is_over=$(awk -v total="$total_cost" -v limit="$current_limit" 'BEGIN {print (total > limit) ? 1 : 0}')

  if [[ "$is_over" -eq 1 ]]; then
    echo "CRITICAL: Budget exceeded (\$$total_cost > \$$current_limit)" >&2
    return 1
  fi

  echo "$total_cost"
  return 0
}

# report_costs
report_costs() {
  if [[ ! -f "$COST_FILE" ]]; then
    echo "No cost data found at $COST_FILE"
    return
  fi

  echo "Cost Summary"
  echo "============"
  echo "Budget Limit: \$$BUDGET_LIMIT"
  echo "Log File: $COST_FILE"
  echo ""

  awk -F: '
    BEGIN { printf "%-20s %-15s %-10s %-10s %-10s\n", "Task ID", "Model", "Input", "Output", "Cost ($)" }
    {
      printf "%-20s %-15s %-10s %-10s %-10s\n", $2, $3, $4, $5, $6
      tot_in += $4
      tot_out += $5
      tot_cost += $6
    }
    END {
      print "----------------------------------------------------------------------"
      printf "%-20s %-15s %-10s %-10s %-10s\n", "TOTAL", "", tot_in, tot_out, tot_cost
    }
  ' "$COST_FILE"
}

# Main entry point for CLI usage
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  COMMAND="${1:-}"
  shift || true

  case "$COMMAND" in
    track)
      track_usage "$@"
      ;;
    check)
      check_budget "$@"
      ;;
    report)
      report_costs
      ;;
    clear)
      rm -f "$COST_FILE"
      echo "Cost log cleared."
      ;;
    *)
      echo "Usage: $0 {track|check|report|clear} [args...]"
      exit 1
      ;;
  esac
fi
