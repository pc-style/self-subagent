# Handoff: Implementing Diff-Based Verification (Upgrade #7)

## What We've Done

**Completed:**
1. **Real-World Test Harness (Upgrade #1)** - Fully built and tested with Codex
   - Sample repo with 5 TypeScript modules in `test-harness/sample-repo/`
   - Working test runners for Claude, Codex, Amp, aider
   - Scoring system (Discovery, Correctness, Parallelism)
   - Codex test result: 6/10 overall (10 discovery, 6 correctness, 3 parallelism)

2. **Result Quality Gate (Upgrade #3)** - Implemented and working
   - `skill/quality-gate.sh` script that scores output 0-10
   - Added to SKILL.md Phase 4e
   - Criteria: File Scope (4pts), Validation (4pts), Diff Size (2pts)
   - Threshold: ≥6/10 = ACCEPT, <6/10 = REJECT + retry

**Current Task:**
Implement **Upgrade #7: Diff-Based Verification** - Extend the quality gate with:
- Secret/credential detection in diffs (scan for API keys, tokens)
- Rogue edit detection (only declared targets modified)
- Auto-revert on verification failure
- Integration with wave execution (reject before next wave)

## Files to Load

### Core Implementation
- `skill/SKILL.md` - Main skill file, Phase 4e needs expansion for diff verification
- `skill/quality-gate.sh` - Existing quality gate script to extend
- `skill/references/quality-gate.md` - Reference documentation

### Test Infrastructure  
- `test-harness/` - Full test harness directory
- `test-harness/sample-repo/src/*.ts` - 5 modules for testing
- `test-harness/score-*.sh` - Scoring scripts (patterns to follow)
- `test-harness/results/codex-*/git_diff.patch` - Example diffs for testing

### Context & Requirements
- `docs/propositions.md` - Full upgrade #7 specification
- `docs/HANDOFF.md` - This file (previous handoff context)
- `docs/AGENTS.md` - Amp architecture reference (subagent patterns)
- `skill/references/orchestration.md` - Wave execution patterns

## Implementation Plan for #7

### 1. Create `diff-verify.sh` Script
Extend quality gate with diff analysis:

```bash
# Secret detection patterns
SECRET_PATTERNS=(
  'api[_-]?key\s*[=:]\s*["\'][^"\']{16,}["\']'
  'token\s*[=:]\s*["\'][^"\']{20,}["\']'
  'password\s*[=:]\s*["\'][^"\']+["\']'
  'sk-[a-zA-Z0-9]{32,}'  # OpenAI key pattern
  'ghp_[a-zA-Z0-9]{36}'  # GitHub token pattern
)

# Scan diff for secrets
scan_secrets() {
  local diff_file="$1"
  for pattern in "${SECRET_PATTERNS[@]}"; do
    if grep -E "$pattern" "$diff_file"; then
      echo "POTENTIAL SECRET DETECTED"
      return 1
    fi
  done
}
```

### 2. Extend Quality Gate
Add to `quality-gate.sh`:
- Pre-merge secret scan on git diff
- Rogue file detection (files outside declared targets)
- Auto-revert capability: `git checkout -- .` on failure
- Exit codes: 0=ACCEPT, 1=REJECT, 2=SECRETS_FOUND

### 3. Integrate with Wave Execution
Modify orchestration in `skill/references/orchestration.md`:
```bash
# In reap_finished():
for id in "${!TASK_STATUS[@]}"; do
  if [[ "${TASK_STATUS[$id]}" == "running" ]]; then
    if ! kill -0 "${TASK_PIDS[$id]}" 2>/dev/null; then
      # Run diff verification BEFORE marking done
      if ! verify_diff "$TMPDIR/$id" "${TASK_WRITES[$id]}"; then
        TASK_STATUS[$id]="failed"
        auto_revert "$TMPDIR/$id"
      else
        TASK_STATUS[$id]="done"
      fi
    fi
  fi
done
```

### 4. Secret Detection Patterns
Create comprehensive pattern list:
- Generic: `api[_-]?key`, `secret`, `password`, `token`
- Provider-specific: OpenAI (`sk-`), GitHub (`ghp_`), AWS (`AKIA`)
- High-entropy strings (use `ent` or `shannon` entropy calculation)
- Comment markers: `TODO.*remove`, `FIXME.*key`

### 5. Testing
- Add test case in `test-harness/scenarios/` with embedded secrets
- Verify gate catches secrets in test run
- Test auto-revert functionality

## Key Decisions to Preserve

1. **Quality Gate Integration** - Diff verification should be part of quality gate, not separate
2. **Auto-revert** - On failure, revert changes immediately before proceeding
3. **Fail Fast** - Stop wave execution if secrets detected
4. **Pattern Library** - Keep secret patterns extensible (array in script)
5. **Exit Codes** - Use specific codes: 0=accept, 1=quality fail, 2=secrets found

## Technical Constraints

- Must work with temp directories (test harness pattern)
- Must handle git worktrees (see orchestration.md)
- Must integrate with existing quality gate scoring
- Must not break existing test harness

## Next Steps

1. Create `skill/diff-verify.sh` with secret detection
2. Extend `quality-gate.sh` with diff verification step
3. Add auto-revert to orchestration.md scheduler
4. Create test scenario with secrets
5. Run test harness to verify

## Reference: Upgrade #7 Specification

From `docs/propositions.md`:
> After each subagent completes, instead of just checking exit code, parse `git diff` to verify:
> - Only declared write targets were modified (reject rogue edits)
> - No secrets/credentials were introduced (scan for patterns like API keys, tokens)
> - Diff size is proportional to task complexity (a "rename variable" task producing 500 lines of diff = something went wrong)
> - Auto-revert subagent changes that fail verification before running the next wave.

## Current State

- Working directory: `/Users/pcstyle/projects/self-subagent/`
- Last action: Built quality gate and test harness
- Test results available: `test-harness/results/codex-*/`
- All scripts executable and tested

Ready to implement diff verification next.
