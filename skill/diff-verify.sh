#!/usr/bin/env bash
# Diff-Based Verification (Upgrade #7)
# Scans git diff for secrets, rogue edits, and anomalous diff sizes.
# Integrates with quality-gate.sh as a pre-merge verification step.
#
# Usage: diff-verify.sh <subagent_dir> <results_dir> <expected_files> [task_complexity]
#
# Exit codes:
#   0 = PASS  (diff is clean)
#   1 = FAIL  (rogue edits or anomalous diff)
#   2 = SECRETS_FOUND (potential credentials detected — hard block)

set -euo pipefail

SUBAGENT_DIR="${1:-}"
RESULTS_DIR="${2:-}"
EXPECTED_FILES="${3:-}"
TASK_COMPLEXITY="${4:-medium}"

if [[ -z "$SUBAGENT_DIR" || -z "$RESULTS_DIR" || -z "$EXPECTED_FILES" ]]; then
  echo "Usage: $0 <subagent_dir> <results_dir> <expected_files> [task_complexity]"
  echo ""
  echo "Exit codes: 0=PASS, 1=FAIL, 2=SECRETS_FOUND"
  exit 1
fi

mkdir -p "$RESULTS_DIR"

# ---------------------------------------------------------------------------
# Secret Detection Patterns
# ---------------------------------------------------------------------------
# Each pattern is a POSIX extended regex. We scan only added lines (lines
# starting with '+' in the unified diff, excluding the +++ header).

SECRET_PATTERNS=(
  # Generic credential assignments
  'api[_-]?key\s*[=:]\s*["\x27][^"\x27]{16,}["\x27]'
  'api[_-]?secret\s*[=:]\s*["\x27][^"\x27]{16,}["\x27]'
  'secret[_-]?key\s*[=:]\s*["\x27][^"\x27]{16,}["\x27]'
  'token\s*[=:]\s*["\x27][^"\x27]{20,}["\x27]'
  'password\s*[=:]\s*["\x27][^"\x27]{8,}["\x27]'
  'passwd\s*[=:]\s*["\x27][^"\x27]{8,}["\x27]'
  'auth[_-]?token\s*[=:]\s*["\x27][^"\x27]{16,}["\x27]'
  'access[_-]?token\s*[=:]\s*["\x27][^"\x27]{16,}["\x27]'
  'private[_-]?key\s*[=:]\s*["\x27][^"\x27]{16,}["\x27]'
  'client[_-]?secret\s*[=:]\s*["\x27][^"\x27]{16,}["\x27]'

  # Provider-specific key formats
  'sk-[a-zA-Z0-9]{32,}'               # OpenAI API key
  'sk-proj-[a-zA-Z0-9_-]{40,}'        # OpenAI project key
  'ghp_[a-zA-Z0-9]{36}'               # GitHub personal access token
  'gho_[a-zA-Z0-9]{36}'               # GitHub OAuth token
  'ghs_[a-zA-Z0-9]{36}'               # GitHub server token
  'ghu_[a-zA-Z0-9]{36}'               # GitHub user-to-server token
  'github_pat_[a-zA-Z0-9_]{22,}'      # GitHub fine-grained PAT
  'AKIA[0-9A-Z]{16}'                   # AWS access key ID
  'xox[bpsar]-[0-9a-zA-Z-]{10,}'      # Slack tokens
  'sk_live_[0-9a-zA-Z]{24,}'          # Stripe live secret key
  'rk_live_[0-9a-zA-Z]{24,}'          # Stripe restricted key
  'sq0atp-[0-9A-Za-z_-]{22}'          # Square access token
  'SG\.[0-9A-Za-z_-]{22}\.[0-9A-Za-z_-]{43}'  # SendGrid API key
  'AIza[0-9A-Za-z_-]{35}'             # Google API key
  'ya29\.[0-9A-Za-z_-]{50,}'          # Google OAuth token
  'ANTHROPIC_API_KEY\s*[=:]\s*["\x27]sk-ant-'  # Anthropic key

  # PEM private keys
  'BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY'

  # Connection strings with embedded credentials
  '(mysql|postgres|postgresql|mongodb|redis)://[^:]+:[^@]+@'

  # Suspicious TODO/FIXME markers
  'TODO.*remove.*(key|secret|token|password|credential)'
  'FIXME.*(key|secret|token|password|credential)'
  'HACK.*(key|secret|token|password|credential)'
)

# Allowlist patterns — these are NOT secrets (test fixtures, env refs, etc.)
# NOTE: These are matched case-insensitively. Use word-boundary-like patterns
# to avoid false allowlisting (e.g. "example" would match "AKIAEXAMPLE").
ALLOWLIST_PATTERNS=(
  'process\.env\.'
  'os\.environ'
  '\$\{[A-Z_]+\}'          # Shell variable references
  'getenv\('
  'config\.(get|read)'
  'placeholder'
  '(^|[^A-Za-z])example[_-]' # "example_key", "example-token" but not "AKIAEXAMPLE"
  'your[_-]?api[_-]?key'
  'xxx+'
  'CHANGE_ME'
  'test[_-]?(key|token|secret)'
  'mock[_-]?(key|token|secret)'
  'fake[_-]?(key|token|secret)'
  'dummy[_-]?(key|token|secret)'
)

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------

# Extract only added lines from the diff (real content, not diff headers)
get_added_lines() {
  local dir="$1"
  cd "$dir"
  git diff 2>/dev/null | grep '^+[^+]' | sed 's/^+//' || true
}

# Get the full diff for analysis
get_diff() {
  local dir="$1"
  cd "$dir"
  git diff 2>/dev/null || true
}

# Scan for secrets in added lines
# Returns: number of secrets found. Writes findings to results file.
scan_secrets() {
  local dir="$1"
  local findings_file="$2"
  local added_lines
  local found=0

  added_lines=$(get_added_lines "$dir")

  if [[ -z "$added_lines" ]]; then
    echo "No added lines to scan" > "$findings_file"
    echo 0
    return
  fi

  > "$findings_file"  # truncate

  for pattern in "${SECRET_PATTERNS[@]}"; do
    local matches
    matches=$(echo "$added_lines" | grep -iE -- "$pattern" 2>/dev/null || true)

    if [[ -n "$matches" ]]; then
      # Check each match against the allowlist
      while IFS= read -r match_line; do
        local allowed=false
        for allow_pat in "${ALLOWLIST_PATTERNS[@]}"; do
          if echo "$match_line" | grep -iqE -- "$allow_pat" 2>/dev/null; then
            allowed=true
            break
          fi
        done

        if [[ "$allowed" == false ]]; then
          found=$((found + 1))
          # Redact the actual value for safety
          local redacted
          redacted=$(echo "$match_line" | sed -E 's/([=:]\s*["\x27])[^"\x27]+(["\x27])/\1***REDACTED***\2/g')
          echo "PATTERN: $pattern" >> "$findings_file"
          echo "LINE: $redacted" >> "$findings_file"
          echo "" >> "$findings_file"
        fi
      done <<< "$matches"
    fi
  done

  echo "$found"
}

# Detect rogue edits — files modified outside the declared targets
detect_rogue_edits() {
  local dir="$1"
  local expected="$2"
  local rogue_file="$3"
  local rogue_count=0

  cd "$dir"
  local modified
  modified=$(git diff --name-only 2>/dev/null | sort || true)

  > "$rogue_file"  # truncate

  if [[ -z "$modified" ]]; then
    echo 0
    return
  fi

  for file in $modified; do
    if [[ ! " $expected " =~ " $file " ]]; then
      rogue_count=$((rogue_count + 1))
      echo "ROGUE: $file" >> "$rogue_file"
    fi
  done

  echo "$rogue_count"
}

# Check diff size proportionality
check_diff_proportionality() {
  local dir="$1"
  local complexity="$2"

  cd "$dir"

  # Count actual insertions + deletions (not just stat summary)
  local insertions deletions total
  insertions=$(git diff --numstat 2>/dev/null | awk '{s+=$1} END {print s+0}')
  deletions=$(git diff --numstat 2>/dev/null | awk '{s+=$2} END {print s+0}')
  total=$((insertions + deletions))

  # Thresholds by complexity
  local max_lines
  case "$complexity" in
    small)  max_lines=100 ;;
    large)  max_lines=1000 ;;
    *)      max_lines=400 ;;  # medium
  esac

  echo "$total $max_lines $insertions $deletions"
}

# Auto-revert all changes in a directory
auto_revert() {
  local dir="$1"
  cd "$dir"
  echo "Auto-reverting changes in $dir..."

  # Revert tracked file changes
  git checkout -- . 2>/dev/null || true

  # Remove untracked files that were added
  git clean -fd 2>/dev/null || true

  echo "Revert complete."
}

# ---------------------------------------------------------------------------
# Main Verification
# ---------------------------------------------------------------------------

echo "========================================"
echo "  Diff-Based Verification"
echo "  Directory: $SUBAGENT_DIR"
echo "  Expected: $EXPECTED_FILES"
echo "  Complexity: $TASK_COMPLEXITY"
echo "========================================"
echo ""

PASS=true
SECRETS_FOUND=false
ROGUE_COUNT=0
DIFF_TOTAL=0
DIFF_MAX=0
REPORT=""

# --- 1. Secret Scan ---
echo "[1/3] Scanning for secrets in diff..."

SECRET_COUNT=$(scan_secrets "$SUBAGENT_DIR" "$RESULTS_DIR/secret_findings.txt")

if [[ $SECRET_COUNT -gt 0 ]]; then
  PASS=false
  SECRETS_FOUND=true
  REPORT="${REPORT}SECRETS: $SECRET_COUNT potential secret(s) detected\n"
  echo "  FOUND $SECRET_COUNT potential secret(s)"
  echo "  Details: $RESULTS_DIR/secret_findings.txt"
else
  REPORT="${REPORT}SECRETS: PASS (none detected)\n"
  echo "  PASS: No secrets detected"
fi

# --- 2. Rogue Edit Detection ---
echo ""
echo "[2/3] Checking for rogue edits..."

ROGUE_COUNT=$(detect_rogue_edits "$SUBAGENT_DIR" "$EXPECTED_FILES" "$RESULTS_DIR/rogue_edits.txt")

if [[ $ROGUE_COUNT -gt 0 ]]; then
  PASS=false
  REPORT="${REPORT}ROGUE EDITS: $ROGUE_COUNT file(s) outside declared targets\n"
  echo "  FOUND $ROGUE_COUNT rogue edit(s):"
  cat "$RESULTS_DIR/rogue_edits.txt" | sed 's/^/    /'
else
  REPORT="${REPORT}ROGUE EDITS: PASS (all edits within scope)\n"
  echo "  PASS: All edits within declared scope"
fi

# --- 3. Diff Proportionality ---
echo ""
echo "[3/3] Checking diff proportionality..."

read -r DIFF_TOTAL DIFF_MAX DIFF_INS DIFF_DEL <<< "$(check_diff_proportionality "$SUBAGENT_DIR" "$TASK_COMPLEXITY")"

if [[ $DIFF_TOTAL -gt $DIFF_MAX ]]; then
  PASS=false
  REPORT="${REPORT}DIFF SIZE: FAIL ($DIFF_TOTAL lines, max $DIFF_MAX for $TASK_COMPLEXITY)\n"
  echo "  FAIL: $DIFF_TOTAL lines (+$DIFF_INS/-$DIFF_DEL) exceeds max $DIFF_MAX"
else
  REPORT="${REPORT}DIFF SIZE: PASS ($DIFF_TOTAL lines, max $DIFF_MAX)\n"
  echo "  PASS: $DIFF_TOTAL lines (+$DIFF_INS/-$DIFF_DEL) within threshold ($DIFF_MAX)"
fi

# ---------------------------------------------------------------------------
# Write Verification Report
# ---------------------------------------------------------------------------

cat > "$RESULTS_DIR/diff_verify_report.txt" << EOF
Diff Verification Report
========================
Directory: $SUBAGENT_DIR
Expected Files: $EXPECTED_FILES
Task Complexity: $TASK_COMPLEXITY

Results:
$(echo -e "$REPORT")

Modified Files:
$(cd "$SUBAGENT_DIR" && git diff --name-only 2>/dev/null || echo "N/A")

Diff Stats:
$(cd "$SUBAGENT_DIR" && git diff --stat 2>/dev/null || echo "N/A")

Secret Findings:
$(cat "$RESULTS_DIR/secret_findings.txt" 2>/dev/null || echo "None")

Rogue Edits:
$(cat "$RESULTS_DIR/rogue_edits.txt" 2>/dev/null || echo "None")
EOF

# ---------------------------------------------------------------------------
# Decision
# ---------------------------------------------------------------------------

echo ""
echo "========================================"

if [[ "$SECRETS_FOUND" == true ]]; then
  echo "  BLOCKED: Secrets detected in diff"
  echo "  Action: Auto-revert + reject"
  echo "========================================"
  echo ""

  # Auto-revert on secret detection — this is a hard block
  auto_revert "$SUBAGENT_DIR"
  echo "SECRETS_FOUND" > "$RESULTS_DIR/diff_verify_status"
  exit 2

elif [[ "$PASS" == false ]]; then
  echo "  FAILED: Diff verification failed"
  echo "  Action: Reject (retry or do inline)"
  echo "========================================"
  echo ""

  # Auto-revert rogue/oversized diffs
  auto_revert "$SUBAGENT_DIR"
  echo "FAILED" > "$RESULTS_DIR/diff_verify_status"
  exit 1

else
  echo "  PASSED: Diff verification clean"
  echo "  Action: Proceed to quality gate"
  echo "========================================"
  echo ""

  echo "PASSED" > "$RESULTS_DIR/diff_verify_status"
  exit 0
fi
