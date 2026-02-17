# Propositions: Top 10 Upgrades for self-subagent

## 1. Real-World Test Harness

Build a test suite that runs the skill inside 4+ actual CLIs (Claude Code, Codex, Amp, aider) on a standardized task ("add error handling to 5 modules in a sample repo"). Score each run on: discovery accuracy, parallelism efficiency, output correctness. This is the single fastest way to find bugs in the skill — everything else is theory until it runs.

## 2. Cost & Token Budget System

Add `references/cost-management.md`. Each subagent task gets a budget tier:
- **Research** (read-only): use cheapest model, 2K token cap on output
- **Single-file edit**: mid-tier model, 4K cap
- **Multi-file implementation**: strongest model, 8K cap
- Track cumulative cost across all subagents. Hard-stop if total exceeds user-defined limit. Amp does model selection per-agent type — we should too.

## 3. Result Quality Gate

Before merging any subagent's output, the parent scores it 0-10 on: (a) did it modify only declared files, (b) does typecheck/lint pass, (c) does the diff look reasonable in size. Reject anything below 6 and either retry or do it inline. Amp's `processLibrarianOutput` does a version of this — we need a generalized one.

## 4. Session Resumption for Retries

Claude (`--resume`), Codex (`exec resume`), and Amp all support resuming a previous session. Instead of restarting a failed subagent from scratch (losing all its context), resume it with the error appended. Saves tokens, preserves the subagent's file reads and understanding. Add this as a Phase 4 enhancement in orchestration.md.

## 5. MCP Server Wrapper

Build a lightweight MCP server (`self-subagent-mcp`) that exposes three tools:
- `spawn_subagent(prompt, write_targets, depends_on, timeout)`
- `check_status(task_id)` → running/done/failed
- `collect_results(task_id)` → stdout + exit code + changed files

This makes the skill usable from agents that have MCP access but no direct bash (VS Code extensions, web-based agents). Converts the bash-based orchestration into a tool-calling interface.

## 6. Adaptive Concurrency

Replace the static `MAX_PARALLEL=6` with adaptive throttling based on system load:
- Monitor CPU/memory via `uptime` and `vm_stat` (macOS) or `/proc/loadavg` (Linux)
- Start at 2, ramp up if system is idle, back off if load average exceeds core count
- Track per-subagent wall time — if tasks are getting slower, reduce concurrency
- This is what Amp's ToolRunner effectively does with its resource-key scheduling.

## 7. Diff-Based Verification

After each subagent completes, instead of just checking exit code, parse `git diff` to verify:
- Only declared write targets were modified (reject rogue edits)
- No secrets/credentials were introduced (scan for patterns like API keys, tokens)
- Diff size is proportional to task complexity (a "rename variable" task producing 500 lines of diff = something went wrong)
- Auto-revert subagent changes that fail verification before running the next wave.

## 8. Prompt Compression & Context Sharing

When spawning 5+ subagents that share context (same codebase, same coding style, same type definitions):
- Write shared context to a temp file once
- Each subagent prompt says "Read /tmp/shared-context.md first" instead of inlining the same 2K of types/interfaces in every prompt
- Reduces total tokens by 60-80% for large fan-outs. Amp does this implicitly via its tool service — we need it explicitly.

## 9. Progress Streaming to Parent

Instead of waiting for an entire wave to finish, stream subagent progress:
- Use named pipes (FIFOs) or tailing output files to detect milestones ("reading files...", "writing changes...", "running validation...")
- Parent can report progress to the user in real-time instead of going silent for 5 minutes
- If a subagent stalls (no output for 60s), proactively kill and retry it
- Pattern already sketched in orchestration.md — needs to be promoted to the main SKILL.md workflow.

## 10. Publish as Open-Source Package

Push to GitHub as `pcstyle/self-subagent` (or `agent-skills/self-subagent`):
- Add install instructions for every supported skill directory (`~/.agents/skills/`, `.claude/skills/`, `.cursor/skills/`, `.codex/skills/`)
- Create a one-liner install: `curl -sL .../install.sh | bash`
- Add a CONTRIBUTING.md for community CLI profile additions
- This would be the first truly agent-agnostic orchestration skill in the wild. The Agent Skills format is designed for exactly this kind of sharing.
