# Self-Subagent Real-World Test Harness

Automated testing framework that validates the self-subagent skill across multiple AI coding CLIs on macOS.

## Quick Start

```bash
# Run against all available CLIs
./test-harness/run-all.sh

# Run against specific CLI
./test-harness/runners/run-claude.sh
./test-harness/runners/run-codex.sh
./test-harness/runners/run-amp.sh
./test-harness/runners/run-aider.sh

# Run specific scenario
./test-harness/run-all.sh 01-error-handling
```

## Prerequisites (macOS)

### Required
- macOS with bash
- Git
- Node.js & npm (for TypeScript validation)
- At least one supported CLI installed

### Supported CLIs

**Claude Code** (Anthropic)
```bash
npm install -g @anthropic-ai/claude-code
export ANTHROPIC_API_KEY="your-key"
```

**Codex CLI** (OpenAI)
```bash
npm install -g @openai/codex
export OPENAI_API_KEY="your-key"
```

**Amp** (Sourcegraph)
```bash
# Install from https://amp.dev
amp login
```

**aider**
```bash
pip install aider-chat
# or
brew install aider
```

## Test Structure

### Sample Repository
`test-harness/sample-repo/` - A TypeScript project with 5 modules that need error handling:
- `src/auth.ts` - Authentication functions
- `src/payments.ts` - Payment processing
- `src/user.ts` - User management
- `src/utils.ts` - Utility functions
- `src/api.ts` - API layer

### Test Scenarios
`test-harness/scenarios/01-error-handling/` - Standardized task:
- Add error handling to all 5 modules
- Create custom error classes
- Ensure TypeScript compiles
- Use parallel subagents

## Scoring System

Each test run is scored on three dimensions (0-10 each):

### Discovery Accuracy
Did the subagent modify the right files?
- +2 points per expected file modified
- -1 point per unexpected file modified
- -5 points if expected files missing

### Correctness
Does the code pass validation?
- TypeScript compilation: -4 if fails
- No secrets in code: -3 if found
- Error handling patterns: -2 if missing
- Custom error classes: -1 if missing

### Parallelism Efficiency
Did it use concurrency effectively?
- Based on speedup ratio (sequential_time / actual_time)
- 5-6x speedup = 10/10 (perfect parallelism)
- 4-5x = 9/10 (good parallelism)
- 3-4x = 7-8/10 (moderate)
- 2-3x = 5-6/10 (limited)
- <2x = 2-3/10 (mostly sequential)

## Results

After running, results are saved to:
```
test-harness/results/
├── claude-1234567890/
│   ├── output.log              # Full CLI output
│   ├── scorecard.txt           # Human-readable scores
│   ├── score_discovery         # Numeric score
│   ├── score_correctness
│   ├── score_parallelism
│   ├── git_diff.patch          # All changes made
│   ├── modified_files.txt      # List of changed files
│   └── modified_src/           # Copy of modified source
├── codex-1234567890/
└── ...
```

## Example Output

```
╔════════════════════════════════════════════════════════╗
║              TEST HARNESS SCORECARD                    ║
╠════════════════════════════════════════════════════════╣
║  Discovery:    10/10  ██████████                       ║
║  Correctness:   9/10  █████████░                       ║
║  Parallelism:   7/10  ███████░░░                       ║
╠════════════════════════════════════════════════════════╣
║  OVERALL:       8/10  ████████░░                       ║
╚════════════════════════════════════════════════════════╝
```

## Troubleshooting

### "command not found" errors
Make sure the CLI is installed and on your PATH:
```bash
which claude
which codex
which amp
which aider
```

### Tests timeout (10 minutes)
The test harness uses a 10-minute timeout per CLI. If your system is slower:
1. Edit the runner script (e.g., `runners/run-claude.sh`)
2. Change `timeout 600` to `timeout 1200` for 20 minutes

### No git changes detected
Make sure the test scenario prompt is being processed correctly. Check:
```bash
cat test-harness/results/claude-*/output.log
```

### TypeScript errors in sample repo
The sample repo should compile before running tests:
```bash
cd test-harness/sample-repo
npx tsc --noEmit
```

## Adding New CLIs

1. Create `test-harness/runners/run-<cli>.sh`
2. Copy structure from existing runner
3. Update the execution command for your CLI
4. Make executable: `chmod +x test-harness/runners/run-<cli>.sh`
5. Add detection to `test-harness/run-all.sh`

## Adding New Scenarios

1. Create `test-harness/scenarios/02-your-scenario/`
2. Add `prompt.txt` with the task description
3. Update sample-repo if needed
4. Run: `./test-harness/run-all.sh 02-your-scenario`

## CI Integration

Add to GitHub Actions:

```yaml
name: Test Harness
on: [push]
jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
      - run: npm install -g @anthropic-ai/claude-code
      - run: ./test-harness/runners/run-claude.sh
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

## License

MIT - See main project LICENSE