#!/usr/bin/env bash
# Test: Diff-Based Verification (Upgrade #7)
# Creates scenarios with secrets, rogue edits, and oversized diffs,
# then verifies diff-verify.sh catches each one.
#
# Usage: ./test-harness/test-diff-verify.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIFF_VERIFY="$PROJECT_DIR/skill/diff-verify.sh"
QUALITY_GATE="$PROJECT_DIR/skill/quality-gate.sh"

PASS_COUNT=0
FAIL_COUNT=0
TOTAL=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

setup_test_repo() {
  local dir
  dir=$(mktemp -d)
  cd "$dir"
  git init --quiet
  mkdir -p src
  cat > src/auth.ts << 'TSEOF'
export async function authenticateUser(email: string, password: string) {
  const response = await fetch('/api/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password })
  });
  return response.json();
}
TSEOF
  cat > src/payments.ts << 'TSEOF'
export async function processPayment(userId: string, amount: number) {
  const response = await fetch('/api/payments/process', {
    method: 'POST',
    body: JSON.stringify({ userId, amount })
  });
  return response.json();
}
TSEOF
  git add -A
  git commit -m "initial" --quiet
  echo "$dir"
}

run_test() {
  local name="$1"
  local expected_exit="$2"
  local dir="$3"
  local results="$4"
  local expected_files="$5"
  local complexity="${6:-medium}"

  TOTAL=$((TOTAL + 1))
  echo ""
  echo "--- Test $TOTAL: $name ---"
  echo "  Expected exit: $expected_exit"

  local actual_exit=0
  "$DIFF_VERIFY" "$dir" "$results" "$expected_files" "$complexity" > "$results/test_output.txt" 2>&1 || actual_exit=$?

  if [[ $actual_exit -eq $expected_exit ]]; then
    echo "  PASS (exit=$actual_exit)"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  FAIL (expected=$expected_exit, got=$actual_exit)"
    echo "  Output:"
    cat "$results/test_output.txt" | sed 's/^/    /'
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# ---------------------------------------------------------------------------
# Test 1: Clean diff — should PASS (exit 0)
# ---------------------------------------------------------------------------

REPO1=$(setup_test_repo)
RESULTS1=$(mktemp -d)

cd "$REPO1"
cat >> src/auth.ts << 'TSEOF'

export function validatePassword(password: string): boolean {
  return password.length >= 8;
}
TSEOF

run_test "Clean diff (no secrets, correct scope)" 0 "$REPO1" "$RESULTS1" "src/auth.ts" "small"

# ---------------------------------------------------------------------------
# Test 2: Secret in diff — should BLOCK (exit 2)
# ---------------------------------------------------------------------------

REPO2=$(setup_test_repo)
RESULTS2=$(mktemp -d)

cd "$REPO2"
cat >> src/auth.ts << 'TSEOF'

const OPENAI_KEY = "sk-1234567890abcdef1234567890abcdef12345678";

export async function callOpenAI(prompt: string) {
  return fetch('https://api.openai.com/v1/chat', {
    headers: { 'Authorization': `Bearer ${OPENAI_KEY}` }
  });
}
TSEOF

run_test "OpenAI API key in diff" 2 "$REPO2" "$RESULTS2" "src/auth.ts" "small"

# Verify auto-revert happened
cd "$REPO2"
if git diff --quiet 2>/dev/null; then
  echo "  (auto-revert confirmed: working directory clean)"
else
  echo "  WARNING: auto-revert did not clean working directory"
fi

# ---------------------------------------------------------------------------
# Test 3: GitHub token in diff — should BLOCK (exit 2)
# ---------------------------------------------------------------------------

REPO3=$(setup_test_repo)
RESULTS3=$(mktemp -d)

cd "$REPO3"
cat >> src/auth.ts << 'TSEOF'

const GH_TOKEN = "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij";

export async function getGitHubUser(token: string) {
  return fetch('https://api.github.com/user', {
    headers: { 'Authorization': `token ${GH_TOKEN}` }
  });
}
TSEOF

run_test "GitHub PAT in diff" 2 "$REPO3" "$RESULTS3" "src/auth.ts" "small"

# ---------------------------------------------------------------------------
# Test 4: AWS key in diff — should BLOCK (exit 2)
# ---------------------------------------------------------------------------

REPO4=$(setup_test_repo)
RESULTS4=$(mktemp -d)

cd "$REPO4"
cat >> src/auth.ts << 'TSEOF'

const AWS_ACCESS_KEY = "AKIAIOSFODNN7EXAMPLE";
TSEOF

run_test "AWS access key in diff" 2 "$REPO4" "$RESULTS4" "src/auth.ts" "small"

# ---------------------------------------------------------------------------
# Test 5: Rogue edit (modified undeclared file) — should FAIL (exit 1)
# ---------------------------------------------------------------------------

REPO5=$(setup_test_repo)
RESULTS5=$(mktemp -d)

cd "$REPO5"
# Modify auth.ts (declared) AND payments.ts (NOT declared)
cat >> src/auth.ts << 'TSEOF'

export function validateEmail(email: string): boolean {
  return email.includes('@');
}
TSEOF

cat >> src/payments.ts << 'TSEOF'

export function calculateFee(amount: number): number {
  return amount * 0.029;
}
TSEOF

run_test "Rogue edit (payments.ts not declared)" 1 "$REPO5" "$RESULTS5" "src/auth.ts" "small"

# ---------------------------------------------------------------------------
# Test 6: Allowlisted pattern — should PASS (exit 0)
# ---------------------------------------------------------------------------

REPO6=$(setup_test_repo)
RESULTS6=$(mktemp -d)

cd "$REPO6"
cat >> src/auth.ts << 'TSEOF'

// Safe: references env variable, not hardcoded secret
const apiKey = process.env.API_KEY;
const testToken = "test_token_placeholder";
const mockSecret = "mock_secret_for_tests";
TSEOF

run_test "Allowlisted patterns (env vars, test tokens)" 0 "$REPO6" "$RESULTS6" "src/auth.ts" "small"

# ---------------------------------------------------------------------------
# Test 7: PEM private key — should BLOCK (exit 2)
# ---------------------------------------------------------------------------

REPO7=$(setup_test_repo)
RESULTS7=$(mktemp -d)

cd "$REPO7"
cat >> src/auth.ts << 'TSEOF'

const PRIVATE_KEY = `-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA1234567890abcdefghijklmnopqrstuvwxyz
-----END RSA PRIVATE KEY-----`;
TSEOF

run_test "PEM private key in diff" 2 "$REPO7" "$RESULTS7" "src/auth.ts" "small"

# ---------------------------------------------------------------------------
# Test 8: Connection string with password — should BLOCK (exit 2)
# ---------------------------------------------------------------------------

REPO8=$(setup_test_repo)
RESULTS8=$(mktemp -d)

cd "$REPO8"
cat >> src/auth.ts << 'TSEOF'

const DB_URL = "postgres://admin:supersecretpass@db.example.com:5432/mydb";
TSEOF

run_test "Database connection string with password" 2 "$REPO8" "$RESULTS8" "src/auth.ts" "small"

# ---------------------------------------------------------------------------
# Test 9: Quality gate integration — should BLOCK (exit 2)
# ---------------------------------------------------------------------------

REPO9=$(setup_test_repo)
RESULTS9=$(mktemp -d)

cd "$REPO9"
cat >> src/auth.ts << 'TSEOF'

const API_SECRET = "sk-proj-abcdefghijklmnopqrstuvwxyz1234567890ABCDEFGH";
TSEOF

echo ""
echo "--- Test $((TOTAL + 1)): Quality gate integration (secrets -> exit 2) ---"
TOTAL=$((TOTAL + 1))
QG_EXIT=0
"$QUALITY_GATE" "$REPO9" "$RESULTS9" "src/auth.ts" "small" > "$RESULTS9/qg_output.txt" 2>&1 || QG_EXIT=$?

if [[ $QG_EXIT -eq 2 ]]; then
  echo "  PASS (quality gate exit=2, secrets blocked)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "  FAIL (expected exit=2, got=$QG_EXIT)"
  cat "$RESULTS9/qg_output.txt" | sed 's/^/    /'
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
# Test 10: No changes — should still PASS (exit 0) with "no added lines"
# ---------------------------------------------------------------------------

REPO10=$(setup_test_repo)
RESULTS10=$(mktemp -d)

cd "$REPO10"
# Don't modify anything

echo ""
echo "--- Test $((TOTAL + 1)): No changes (empty diff) ---"
TOTAL=$((TOTAL + 1))
EMPTY_EXIT=0
"$DIFF_VERIFY" "$REPO10" "$RESULTS10" "src/auth.ts" "small" > "$RESULTS10/test_output.txt" 2>&1 || EMPTY_EXIT=$?

# No changes means no rogue edits and no secrets — but also no expected files modified.
# diff-verify checks rogue edits (unmodified expected files are NOT flagged as rogue),
# so this should still pass. The quality gate will catch "no files modified" separately.
if [[ $EMPTY_EXIT -eq 0 ]]; then
  echo "  PASS (exit=0, empty diff is not a diff-verify failure)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "  FAIL (expected exit=0, got=$EMPTY_EXIT)"
  cat "$RESULTS10/test_output.txt" | sed 's/^/    /'
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "========================================"
echo "  Diff Verification Test Results"
echo "========================================"
echo "  Total: $TOTAL"
echo "  Passed: $PASS_COUNT"
echo "  Failed: $FAIL_COUNT"
echo "========================================"

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo "  SOME TESTS FAILED"
  exit 1
else
  echo "  ALL TESTS PASSED"
  exit 0
fi
