# CLI Discovery and Profiles

Comprehensive guide to discovering and using non-interactive execution modes across AI coding CLIs.

## Universal Discovery Procedure

Run this **every time** you encounter an unfamiliar CLI. Do not rely on hardcoded profiles alone — CLIs update frequently.

### Step 1: Identify the binary

```bash
# What's running me?
ps -p $PPID -o comm= 2>/dev/null

# What's available?
for cmd in amp claude codex cursor opencode aider pi goose cline roo \
           windsurf copilot zed marscode devpilot tabby continue bolt \
           sweep pear void aide kodu trae; do
  command -v "$cmd" &>/dev/null && echo "FOUND: $cmd ($(which $cmd))"
done
```

### Step 2: Read help and scan for execute mode

```bash
CLI=claude  # replace with discovered binary

# Top-level help
$CLI --help 2>&1 | grep -iE 'exec|run|print|batch|pipe|headless|non.?interactive|-[pxe] '

# Check subcommands
$CLI exec --help 2>&1
$CLI run --help 2>&1

# Check for version (useful for docs lookup)
$CLI --version 2>&1
```

Patterns to look for:
- **Explicit exec mode**: `exec`, `run`, `-x`, `execute`
- **Print/pipe mode**: `-p`, `--print`, `--pipe`, `--batch`
- **Headless/non-interactive**: `--headless`, `--non-interactive`, `--no-ui`
- **Stdin support**: mentions of piping, stdin, `-` as argument
- **Auto-approve**: `--yes`, `--auto-approve`, `--full-auto`, `--dangerously-*`, `--no-confirm`, `--yolo`
- **Output format**: `--json`, `--output-format`, `--stream-json`, `--machine-readable`

### Step 3: Test with a trivial prompt

```bash
# Replace with your discovered command pattern
echo "Reply with exactly the word PONG" | timeout 30 $CLI -p 2>&1
```

If it outputs something containing "PONG" — you're good. If it hangs, errors, or opens a UI — try a different flag combination.

### Step 4: Search docs if --help is insufficient

Try these in order:
1. Check for local docs: `$CLI docs`, `man $CLI`, `$CLI help exec`
2. Search the project: look for `AGENTS.md`, `CLAUDE.md`, `README.md`, `.cursorrules`
3. Web search: `"<cli-name> non-interactive mode site:github.com"` or `"<cli-name> exec mode"`
4. Check the CLI's GitHub repo README and issues

## Known Profiles

### Amp (Sourcegraph)

```bash
amp -x "prompt"                           # non-interactive
amp -x --dangerously-allow-all "prompt"   # skip approvals
amp -x --stream-json "prompt"             # JSON output
echo "prompt" | amp -x                    # stdin
amp -x --model claude-sonnet-4 "prompt"   # model override
```

Discovery keywords in `--help`: `-x`, `execute`, `--dangerously-allow-all`, `--stream-json`

### Claude Code (Anthropic)

```bash
claude -p "prompt"                                    # print mode (non-interactive)
claude -p --dangerously-skip-permissions "prompt"      # skip permissions
claude -p --output-format json "prompt"                # JSON output
claude -p --system-prompt "You are an executor." "prompt"  # custom system prompt
claude -p --allowedTools "Read,Write,Bash" "prompt"    # limit tools
claude -p --resume SESSION_ID "follow-up"              # resume session
echo "prompt" | claude -p                              # stdin
```

Discovery keywords: `-p`, `--print`, `--dangerously-skip-permissions`, `--output-format`, `--allowedTools`

### Codex CLI (OpenAI)

```bash
codex exec "prompt"                          # exec mode
codex exec --full-auto "prompt"              # auto-approve in sandbox
codex exec --yolo "prompt"                   # no sandbox, no approvals (dangerous)
codex exec --json "prompt"                   # JSON output
codex exec --cd /path "prompt"               # set workspace root
codex exec --model gpt-5.2-codex-high "prompt"  # model override
codex exec resume SESSION_ID "prompt"        # resume session
```

**Note**: Codex requires a git repo. Workaround: `dir=$(mktemp -d) && git -C "$dir" init && codex exec --cd "$dir" "prompt"`

Discovery keywords: `exec`, `--full-auto`, `--json`, `--cd`

### aider

```bash
echo "prompt" | aider --yes-always --no-stream                    # basic
echo "prompt" | aider --yes-always --no-stream src/a.ts src/b.ts  # with files
echo "prompt" | aider --yes-always --no-stream --model claude-sonnet-4  # model
```

aider uses stdin piping instead of a dedicated exec flag. `--yes-always` prevents confirmation prompts.

Discovery keywords: `--yes-always`, `--no-stream`, `--message`

### Cursor

```bash
cursor --agent "prompt"              # agent mode (if available)
cursor composer --no-ui "prompt"     # no-UI composer
```

Cursor's CLI support varies significantly by version. **Always check `cursor --help`** — the flags change between releases.

### OpenCode

```bash
opencode run "prompt"
```

Discovery keywords: `run`

### Pi Coding Agent

```bash
pi -p "prompt"                                           # non-interactive
pi -p --provider anthropic --model claude-sonnet-4 "prompt"  # provider/model
```

Discovery keywords: `-p`, `--provider`

### goose (Block)

```bash
goose session --non-interactive "prompt"
echo "prompt" | goose session --non-interactive
```

Discovery keywords: `--non-interactive`, `session`

### Cline / Roo Code

These primarily run as VS Code extensions. CLI access varies:
```bash
# Check if they expose a CLI
cline --help 2>&1
roo --help 2>&1
# If not available as CLI, these cannot be used as subagents
```

### Windsurf / Cascade

```bash
windsurf --help 2>&1  # check for CLI mode
# Windsurf is primarily an IDE — CLI subagent use may not be available
```

### Generic: Any CLI with stdin support

Many CLIs accept prompts via stdin even without explicit exec flags:

```bash
echo "Your prompt here" | $CLI 2>&1
printf '%s' "Your prompt here" | $CLI --no-interactive 2>&1
$CLI < prompt.txt 2>&1
```

## Output Capture

### Plain text
```bash
OUTPUT=$($AGENT_CMD "prompt" 2>&1)
EXIT_CODE=$?
```

### JSON (when supported)
```bash
# Amp
amp -x --stream-json "prompt" 2>/dev/null | jq -s 'last'

# Claude Code
claude -p --output-format json "prompt" 2>/dev/null | jq '.result'

# Codex
codex exec --json "prompt" 2>/dev/null | tail -1 | jq '.'
```

### To file (recommended for subagents)
```bash
$AGENT_CMD "prompt" > "$TMPDIR/task.out" 2>&1
```

### Timeout wrapper (always use)
```bash
timeout 300 $AGENT_CMD "prompt" > "$TMPDIR/task.out" 2>&1
# macOS: use gtimeout from coreutils if timeout is unavailable
# brew install coreutils && gtimeout 300 $AGENT_CMD "prompt"
```

## Building Your AGENT_CMD String

After discovery, construct the full command:

```bash
# Minimal (just exec mode)
AGENT_CMD="claude -p"

# With auto-approve (for tasks that edit files)
AGENT_CMD="claude -p --dangerously-skip-permissions"

# With JSON output (for structured collection)
AGENT_CMD="claude -p --dangerously-skip-permissions --output-format json"

# With system prompt (to set the subagent role)
AGENT_CMD="claude -p --dangerously-skip-permissions --system-prompt 'You are a focused executor.'"
```

Verify it works before spawning real tasks:
```bash
echo "Reply PONG" | timeout 30 $AGENT_CMD 2>&1 | grep -q PONG && echo "OK" || echo "FAIL"
```
