# Handoff: Implementing MCP Server Wrapper (Upgrade #5)

## What We've Done

**Completed:**

1. **Real-World Test Harness (Upgrade #1)**
   - Sample repo, runners for Claude/Codex/Amp, scoring system.
   - Verified functionality.

2. **Result Quality Gate (Upgrade #3)**
   - `skill/quality-gate.sh` scores outputs 0-10.
   - Enforces file scope, validation (tsc/lint/test), and diff size.

3. **Diff-Based Verification (Upgrade #7)**
   - `skill/diff-verify.sh` scanner implemented.
   - Detects secrets (25+ patterns), rogue edits, and oversized diffs.
   - Auto-reverts changes on failure.

4. **Cost & Token Budget System (Upgrade #2)**
   - `skill/cost-tracker.sh` tracks usage and enforces budget limits.
   - `skill/references/cost-management.md` defines budget tiers.
   - Integrated budget checks into orchestration.

5. **Session Resumption for Retries (Upgrade #4)**
   - Updated `skill/SKILL.md` to prioritize `--resume`.
   - Modified `skill/references/orchestration.md` `retry_with_context` logic.
   - Detects Session IDs from logs (Claude Code pattern).
   - Verified with `test-harness/test-resume.sh` (5/5 tests passed).

6. **Prompt Compression & Context Sharing (Upgrade #8)**
   - Created `skill/context-packer.sh` to aggregate files.
   - Updated `SKILL.md` Phase 3 with context sharing instructions.
   - Verified with `test-harness/test-context-sharing.sh` (7/7 tests passed).

**Current Task:**
Implement **Upgrade #5: MCP Server Wrapper** - Build a lightweight Model Context Protocol (MCP) server to expose the skill as a set of tools (`spawn_subagent`, `check_status`, `collect_results`). This allows agents like Claude Desktop or VS Code extensions to use the skill without dropping into a raw bash shell.

## Files to Load

### Core Implementation
- `skill/SKILL.md` - Main skill file.
- `skill/references/orchestration.md` - Core logic to wrap.

### Context & Requirements
- `docs/propositions.md` - Full upgrade #5 specification.
- Official MCP SDK documentation (Python or TypeScript).

## Implementation Plan for #5

### 1. Choose Stack
Use **Python** with `uv` (as per user rules) and the `mcp` package for quick implementation.
- `src/server.py`: Main entry point.

### 2. Define Tools
Expose the bash scripts as MCP tools:

- `spawn_subagent(prompt: str, write_targets: str, depends_on: str = "")`
  - Wraps the wave dispatcher logic.
  - Returns a Task ID.

- `check_status(task_id: str)`
  - Reads `TASK_STATUS` (or file-based equivalent).
  - Returns "running", "done", "failed".

- `collect_results(task_id: str)`
  - Returns content of `output.log` and `diff_verify_report.txt`.

### 3. Implementation Details
The server needs to maintain state (the task graph). Since the bash scripts are currently designed for one-shot execution or interactive loops, we might need to:
- Adapt `orchestration.md` into a persistent background process or...
- Have the Python server manage the state and just call individual subagent commands using the CLI profiles.

*Decision*: The Python server will act as the Orchestrator, replacing the `while` loop in `orchestration.md`, but reusing the `diff-verify.sh` and `quality-gate.sh` scripts for verification.

### 4. Testing
- Create `test-harness/test-mcp.py` to simulate an MCP client calling the tools.

## Technical Constraints

- Must work with `uv` for dependency management.
- Must respect the existing `SKILL.md` protocols (verification, cost tracking).
- The MCP server must be able to spawn the user's CLI (Claude/Amp/etc.) — requires `PATH` access.

## Next Steps

1. Initialize `mcp-server/` directory with `pyproject.toml` (using `uv`).
2. Implement `src/server.py` using FastMCP or standard MCP SDK.
3. Map tools to existing bash scripts.
4. Verify with a test client.

## Reference: Upgrade #5 Specification

From `docs/propositions.md`:
> Build a lightweight MCP server (`self-subagent-mcp`) that exposes three tools:
> - `spawn_subagent(prompt, write_targets, depends_on, timeout)`
> - `check_status(task_id)` → running/done/failed
> - `collect_results(task_id)` → stdout + exit code + changed files
> This makes the skill usable from agents that have MCP access but no direct bash.

## Current State

- Working directory: `/Users/pcstyle/projects/self-subagent/`
- Last action: Completed Prompt Compression (Upgrade #8).
- All tests passing.