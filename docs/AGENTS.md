# Amp Subagent Architecture — Code Map

This directory contains the deobfuscated source of Sourcegraph's Amp CLI and a reverse-engineered `self-subagent` skill modeled on its internals.

## Deobfuscated Chunks

All chunks live in `deobfuscation_chunks/`. The original 8.6MB `main.js` was split into 7 chunks and deobfuscated into readable code.

### chunk_01_deobfuscated.js — Core Agent Logic

| Lines | What | Why It Matters |
|-------|------|----------------|
| 128-260 | `generateDefaultSystemPrompt()` | The full system prompt. Defines 3 subagent types (Task, Oracle, Codebase Search), parallel execution policy, serialization rules for write conflicts |
| 155-176 | Parallel Execution Policy | Rules for when to parallelize vs serialize — disjoint write targets, shared contracts, chained transforms |
| 201-231 | Subagent type definitions | Task = "fire-and-forget junior engineer", Oracle = "senior advisor with reasoning model", Codebase Search = "concept-based code finder" |
| 266-269 | `getBestPracticesDoc()` | Workflow: Oracle (plan) → Codebase Search (validate) → Task (execute) |
| 278-331 | `generateSystemPromptWithOptions()` | Rush mode prompt — speed-first, ultra-concise, massive parallel tool calls |
| 349-411 | `generateRushModePrompt()` | Subagent-optimized prompt variant with minimal tokens |
| 419-434 | `generateCustomAgentPrompt()` | Template for named custom agents |

### chunk_02_deobfuscated.js — Subagent Spawning & Tools

| Lines | What | Why It Matters |
|-------|------|----------------|
| 2299-2342 | `runLibrarianSubagent()` | **The concrete subagent spawn pattern**: creates messages, selects tools by provider, builds system prompt, calls `new AgentRunner().run()` with inference config + spec + context, pipes output through `map(processLibrarianOutput)` |
| 2310-2313 | Agent spec construction | `{...AGENT_CONFIGS.librarian, includeTools: availableTools}` — how tool sets are scoped per subagent |
| 2316-2331 | `createRunner()` inner function | The actual `AgentRunner().run(OPENAI_INFERENCE_CONFIG, {systemPrompt, model, spec}, {conversation, toolService, env})` call |
| 2347-2359 | `buildLibrarianSystemPrompt()` | Provider-specific prompt construction (GitHub vs Bitbucket) |
| 2490-2519 | `LIBRARIAN_BASE_PROMPT` | Full system prompt for the Librarian subagent — "You are running inside an AI coding system as a subagent" |
| 900-958 | Bitbucket tool spec | Example of how tools are defined with input schemas |

### chunk_01_deobfuscated.js — ToolRunner & Execution Engine

| Lines | What | Why It Matters |
|-------|------|----------------|
| 469-559 | `buildPromptHashMetadata()` / `trackPromptChanges()` | Prompt change detection — hashes each component, logs diffs between builds |
| 571-592 | `getWorkspaceEnvironment()` | How subagents inherit workspace roots and working directory |
| 602-670 | `buildGuidanceBlocks()` | AGENTS.md file discovery and injection into agent context |

### chunk_05_deobfuscated.js — CLI Entry Point

| Lines | What | Why It Matters |
|-------|------|----------------|
| ~1-50 | CLI argument parsing | `-x` (execute mode), `--dangerously-allow-all`, `--stream-json`, `--model` flag handling |

### chunk_06_deobfuscated.js — Thread & Session Management

| Lines | What | Why It Matters |
|-------|------|----------------|
| ~1-100 | Thread listing, spinner, error handlers | How Amp manages concurrent thread state and reports errors from subagents |

## Key Architectural Patterns

### Subagent Spawning
```
AgentRunner.run(inferenceConfig, {systemPrompt, model, spec: {includeTools}}, {conversation, toolService, env})
  → returns Observable stream with status updates (in-progress, done, error, blocked-on-user)
```

### Resource Locking (ToolRunner)
- Tools declare `serial: true` or `resourceKeys: [{key, mode: "read"|"write"}]`
- Two tools sharing a write key on the same resource → serialize
- Read-read or disjoint keys → parallel
- This is the model our `self-subagent` skill replicates with file-level write locks

### Error Recovery
- Failed subagent output is summarized (via Gemini) and fed back to the parent agent
- Parent decides whether to retry with context or handle inline

### Permission Contexts
- `"subagent"` vs `"thread"` execution context
- Subagents inherit thread ID, working directory, config, tool service, and environment from parent

## Self-Subagent Skill

The `self-subagent/` directory contains the finished skill that teaches any AI coding CLI to replicate this architecture. See `self-subagent/SKILL.md` for the full workflow.
