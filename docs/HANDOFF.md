# HANDOFF.md

## What We're Building

An open-source, agent-agnostic **self-subagent** skill — a SKILL.md that teaches any AI coding CLI agent (Amp, Claude Code, Codex, Cursor, OpenCode, aider, goose, etc.) to orchestrate parallel sub-tasks by spawning non-interactive copies of itself. The architecture was reverse-engineered from Sourcegraph's Amp CLI.

## Current State: Skill v2 Complete

The skill is fully built, validated, and deployed to 3 locations:

```
~/.agents/skills/self-subagent/     ← source of truth
~/projects/skills/self-subagent/    ← copy
~/skills/self-subagent/             ← copy
```

Structure:
```
self-subagent/
├── SKILL.md                          (285 lines)
├── references/
│   ├── cli-profiles.md               (236 lines)
│   └── orchestration.md              (332 lines)
```

All validation passes: name valid, description under 1024 chars, no extraneous files.

## How the Skill Works

4 phases any AI agent follows:

1. **Discover** — Identify your own CLI binary, run `--help`, grep for exec/print/batch flags, test with a PONG prompt, fall back to web search if needed
2. **Decompose** — Build a dependency graph of tasks with `id`, `writes`, `reads`, `depends_on`. Group into waves (sets of tasks safe to run in parallel)
3. **Prompt** — Write self-contained prompts per subagent using a structured template (ROLE/GOAL/MODIFY/CONSTRAINTS/VALIDATION/CONTEXT)
4. **Spawn/Collect/Verify** — Launch waves via background shell processes, collect stdout, retry failures once with error context injected, verify each wave with typecheck/test/lint before proceeding

## Key Files to Load

```
~/.agents/skills/self-subagent/SKILL.md
~/.agents/skills/self-subagent/references/cli-profiles.md
~/.agents/skills/self-subagent/references/orchestration.md
```

### Amp Reverse Engineering (source material)
```
~/amp-extract/node_modules/@sourcegraph/amp/dist/deobfuscation_chunks/chunk_01_deobfuscated.js
~/amp-extract/node_modules/@sourcegraph/amp/dist/deobfuscation_chunks/chunk_02_deobfuscated.js
```

Key sections in the deobfuscated code:
- `chunk_01` lines 128-260: System prompt — subagent types (Task/Oracle/Codebase Search), parallel execution policy, serialization rules
- `chunk_01` lines 278-411: Rush mode and custom agent prompts
- `chunk_02` lines 2299-2342: `runLibrarianSubagent()` — concrete subagent spawning with AgentRunner
- `chunk_02` lines 2490-2519: Librarian system prompt — how Amp instructs its subagents

### Existing skills (for reference, not dependencies)
```
~/.agents/skills/subagent/SKILL.md              — Codex-specific subagent (our skill replaces this)
~/.agents/skills/coding-agent/SKILL.md          — multi-CLI background process patterns
~/.agents/skills/skill-creator/SKILL.md         — skill creation guidelines
```

## Decisions Made

- **Agent-agnostic by design**: The skill does NOT hardcode any specific CLI. It teaches the agent to discover its own execute mode via `--help` + web search.
- **Dependency graphs over flat lists**: Tasks declare write targets and dependencies. The scheduler computes waves automatically and prevents write conflicts.
- **Discovery-first**: Known CLI profiles are a quick-reference table, not the primary mechanism. The agent always checks `--help` first.
- **Retry once, then inline**: Subagent failures get 1 retry with error context injected. After that, the parent agent does the work itself.
- **Max 6 concurrent**: Hard limit on parallel subagents to avoid resource contention.
- **No .skill zip packaging**: User explicitly requested the skill as a directory, not packaged.

## Suggested Next Steps

1. **Real-world testing** — Run the skill in Claude Code, Codex, and Amp on a concrete task (e.g. "add error handling to 5 modules"). Each will exercise different discovery paths.

2. **Cost/token budget management** — Add `references/cost-management.md` covering per-task model selection (cheap model for research, strong for execution), token budget caps, and total-cost tracking.

3. **Result quality scoring** — Parent agent scores subagent output (0-10) before merging. Reject low-quality results. Mirrors Amp's `processLibrarianOutput`.

4. **Session resumption** — Claude/Codex/Amp support `--resume SESSION_ID`. Add a retry pattern that resumes failed subagents instead of restarting from scratch.

5. **MCP server wrapper** — Expose `spawn_subagent`, `check_status`, `collect_results` as MCP tools for agents without bash access.

6. **Publish to GitHub** — Push as `agent-skills/self-subagent` for community use. First truly agent-agnostic orchestration skill.

## User Preferences

- Prefers bold, direct output. No filler.
- Wants skills to be directories (not .skill zips) during development.
- Skill copies must live at `~/.agents/skills/`, `~/projects/skills/`, and `~/skills/`.
- Uses Bun as primary runtime, Next.js App Router, Tailwind v4, Convex backend.
- Conventional commits for git.
