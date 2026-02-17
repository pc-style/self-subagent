# Result Quality Gate

Automated scoring system for subagent output before merging changes.

## Overview

The quality gate runs in two phases:

### Phase 0: Diff-Based Verification (pre-check)

Before any expensive validation, `diff-verify.sh` scans the raw `git diff`:

1. **Secret Scan**: Detects API keys, tokens, credentials in added lines (25+ patterns)
2. **Rogue Edit Detection**: Flags files modified outside declared targets
3. **Diff Proportionality**: Ensures diff size matches task complexity

On failure, changes are **auto-reverted** (`git checkout -- . && git clean -fd`).

### Phase 1: Quality Scoring

Scores subagent output 0-10 on:

1. **File Scope** (4 points): Only modified declared files
2. **Validation** (4 points): Typecheck/lint/tests pass  
3. **Diff Size** (2 points): Changes proportional to task

## Usage

```bash
# Full pipeline (diff verification + quality scoring)
./skill/quality-gate.sh <subagent_dir> <results_dir> <expected_files> [complexity]

# Diff verification only
./skill/diff-verify.sh <subagent_dir> <results_dir> <expected_files> [complexity]

# Example
./skill/quality-gate.sh \
  /tmp/subagent-worktree \
  ./results \
  "src/auth.ts src/payments.ts" \
  medium
```

## Exit Codes

| Code | Meaning | Trigger |
|------|---------|---------|
| `0` | ACCEPT | Diff clean + score >= 6 |
| `1` | REJECT | Diff failed OR score < 6 |
| `2` | SECRETS_FOUND | Hard block, auto-reverted |

## Scoring

| Score | Decision | Action |
|-------|----------|--------|
| 10 | Perfect | Merge immediately |
| 8-9 | Good | Merge with note |
| 6-7 | Acceptable | Merge, monitor next wave |
| 5 | Borderline | Retry with context |
| <5 | Reject | Retry once, then inline |

## Secret Detection

Patterns scanned in added diff lines:

| Category | Examples |
|----------|----------|
| Generic | `api_key=`, `secret=`, `password=`, `token=` |
| OpenAI | `sk-...` (32+ chars), `sk-proj-...` |
| GitHub | `ghp_`, `gho_`, `ghs_`, `ghu_`, `github_pat_` |
| AWS | `AKIA` + 16 uppercase chars |
| Stripe | `sk_live_`, `rk_live_` |
| Slack | `xox[bpsar]-` |
| Google | `AIza`, `ya29.` |
| PEM keys | `BEGIN PRIVATE KEY` |
| DB strings | `postgres://user:pass@host` |

**Allowlisted** (not flagged): `process.env`, `os.environ`, `${VAR}`, `test_key`, `mock_secret`, `placeholder`

## Integration

### In Wave Execution

```bash
for id in "${TASK_NAMES[@]}"; do
  if ./skill/quality-gate.sh \
       "$TMPDIR/$id-worktree" \
       "$RESULTS_DIR/$id" \
       "${TASK_WRITES[$id]}" \
       "medium"; then
    # Merge changes
    git merge "subagent/$id" --no-edit
  else
    FAILED_TASKS+=("$id")
  fi
done
```

### With Retry

```bash
if [[ $QUALITY_SCORE -lt 6 ]]; then
  # Retry with quality report context
  RETRY_PROMPT="$ORIGINAL_PROMPT

QUALITY GATE FAILED (Score: $QUALITY_SCORE/10)

Issues to fix:
$(cat $RESULTS_DIR/quality_report.txt)

Please address these issues."

  timeout 300 $AGENT_CMD "$RETRY_PROMPT" > retry.out 2>&1
fi
```

## Output

The gate creates:
- `quality_score` - Numeric score (0-10)
- `quality_report.txt` - Detailed breakdown with Phase 0 + Phase 1 results
- `diff_verify_status` - PASSED, FAILED, or SECRETS_FOUND
- `diff_verify_report.txt` - Full diff verification details
- `secret_findings.txt` - Redacted secret matches (if any)
- `rogue_edits.txt` - List of files modified outside declared targets

## Complexity Thresholds

| Complexity | Max Lines (quality gate) | Max Lines (diff verify) | Typical Task |
|------------|------------------------|------------------------|--------------|
| small | 50 | 100 | Rename variable, fix typo |
| medium | 200 | 400 | Add error handling to 1 file |
| large | 500 | 1000 | Multi-file refactoring |

## Testing

Run the verification test suite:

```bash
./test-harness/test-diff-verify.sh
```

Tests cover: clean diffs, OpenAI/GitHub/AWS/Stripe keys, PEM keys, connection strings, rogue edits, allowlisted patterns, quality gate integration, and empty diffs.

## Best Practices

1. **Run on every subagent output** - Don't skip verification
2. **Fail fast** - Secrets = hard block, no retry
3. **Auto-revert on failure** - Keep working directory clean
4. **Retry once for quality failures** - Give subagent context to fix
5. **Track scores** - Monitor quality trends
6. **Extend patterns** - Add provider-specific patterns as needed

## See Also

- Main skill: `../SKILL.md` (Phase 4e: Diff Verification, Phase 4f: Quality Gate)
- Orchestration: `orchestration.md` (reap_finished with verification)
- Test harness: `../../test-harness/` (uses similar scoring)