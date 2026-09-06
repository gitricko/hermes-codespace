# Memory Automation: Mnemon Persistence Workflow

## Overview

This article documents the reference architecture for the automated Mnemon memory persistence workflow used by Hermes. It covers recall on session start, recall before each turn, and auto-save after each response via delegated subagent.

## Mnemon Tool Signatures

These are real Hermes plugin tools exposed by the `gitricko/hermes-plugin-mnemon` plugin:

```python
mnemon_remember(text, category, importance, entities, tags)  # Save insight
mnemon_recall(query, intent, limit)                          # Recall insights
mnemon_forget(insight_id)                                    # Soft-delete insight
```

## Categories

| Category | When to use |
|----------|-------------|
| `fact` | Objective information about the user, project, or environment |
| `preference` | User's likes, dislikes, stylistic choices, workflow preferences |
| `decision` | Architectural decisions, tool choices, design decisions |
| `insight` | Non-obvious findings, troubleshooting steps, workarounds |
| `context` | Session-level context that's useful across sessions |
| `general` | Anything that doesn't fit above |

## Importance Levels

| Level | When to use |
|-------|-------------|
| 5 | Critical — user identity, core preferences, security constraints |
| 4 | Important — project goals, recurring preferences, key constraints |
| 3 | Normal — useful context, typical insights |
| 2 | Minor — nice-to-know details |
| 1 | Trivial — barely worth saving (use rarely) |

## Recall Patterns

### Full Context Load (Session Start)

Called by the SessionStart hook:
```python
mnemon_recall(query="", intent="GENERAL", limit=20)
```
Loads the 20 most relevant past insights into context. No specific query needed — just a broad sweep.

### Topic-Specific Recall (Before Responding)

If the hook returns nothing but the topic references past work:
```python
mnemon_recall(query="<topic keywords>", intent="GENERAL", limit=10)
```
Use the user's message topic as the query. Include key terms, project names, and domain-specific vocabulary.

### Intent-Targeted Recall

```python
# When you need to understand WHY a decision was made:
mnemon_recall(query="<topic>", intent="WHY", limit=5)

# When you need to know WHEN something happened:
mnemon_recall(query="<topic>", intent="WHEN", limit=5)

# When you need info about a specific entity:
mnemon_recall(query="<entity name>", intent="ENTITY", limit=5)
```

## Save Patterns

### Direct Tool Call (Preferred for Simple Saves)

`mnemon_remember` is a real Hermes plugin tool. Call it directly from your toolset — no subagent, no CLI invocation needed:

```python
mnemon_remember(
    text="User prefers concise responses and bullet points over prose.",
    category="preference",
    importance=4,
    entities=["gitricko"],
    tags=["communication-style", "user-preference"]
)
```

**Use direct calls when:**
- Saving a single fact or preference inline during a response
- The save is straightforward — no extraction, no multi-item batch
- You're already in a turn; just batch the tool call with whatever else you're doing

### Delegated Save (Bulk or After Complex Responses)

For bulk saves (3+ items) or when context is tight, delegate to a subagent with `toolsets=["terminal"]`. The subagent uses the `mnemon remember` CLI since plugin tools may not propagate to child sessions:

```python
delegate_task(
    goal="Save insights to mnemon memory",
    context="""
Save the following to mnemon memory:

1. text="User prefers bullet-point summaries over paragraphs."
   category="preference", importance=4,
   entities=["gitricko"], tags=["communication-style"]

2. text="The project uses FastAPI with PostgreSQL."
   category="fact", importance=3,
   entities=["project-name"], tags=["tech-stack"]
For each item run: mnemon remember "<text>" \
  --cat <category> --imp <N> \
  --entities e1,e2 \
  --tags "t1,t2"
Binary: /usr/local/bin/mnemon.
""",
    toolsets=["terminal"]
)
```

**Use delegated saves when:**
- Saving 3+ items at once
- The save requires extraction or reasoning
- You're low on context tokens and want the work offloaded

### Decision Guide: Direct vs Delegated

| Condition | Method | Reasoning |
|-----------|--------|-----------|
| 1–2 items, simple | Direct `mnemon_remember()` tool call | Zero overhead — inlined with response |
| 3+ items | Delegate to subagent with CLI | Worth the ~20K token spawn cost for bulk |
| Save requires extraction/analysis | Delegate to subagent | Extraction logic is better offloaded |
| Already doing other tool calls | Batch `mnemon_remember()` with them | Same turn, no extra cost |
| User explicitly asks for delegation | Always delegate | User preference overrides efficiency |

### CLI Flags vs Tool Parameters (Subagent Use Only)

When delegating to a subagent, it runs the `mnemon` CLI — not the plugin tool:

| Tool parameter | CLI flag | Notes |
|---|---|---|
| `text` | positional arg | First argument, not a flag |
| `category` | `--cat` | e.g. `--cat preference` |
| `importance` | `--imp` | e.g. `--imp 4` |
| `entities` | `--entities` | Comma-separated: `entity1,entity2` |
| `tags` | `--tags` | Comma-separated: `tag1,tag2` |

## When to Auto-Save (After Every Response)

After every user-facing response, scan the exchange for anything on this list:

| Signal | What to save |
|--------|-------------|
| User stated a preference | Save as `preference` |
| User made a decision | Save as `decision` |
| User corrected you | Save as `preference` or `fact` |
| You discovered a workaround | Save as `insight` |
| User revealed personal info | Save as `fact`, importance=5 |
| User said "remember this" | Save whatever follows |
| Project architecture detail | Save as `fact` |
| Tool configuration quirk | Save as `insight` |

**When in doubt, save it.** Extra memories are cheap; missing ones are expensive.

## What NOT to Save

- Code the repo already tracks (git history)
- Public API docs or well-known facts
- Transient state ("how are you?", current time)
- Things already in `.hermes.md`, `AGENTS.md`, or other config files

## Example: Full Turn Cycle

```
Session Start → mnemon_recall("", limit=20) → preloaded context

User: "I prefer using ruff over black for formatting."
  → Hook: auto mnemon_recall("ruff black formatting", limit=10)
  → Respond
  → Direct: mnemon_remember(
       text="User prefers ruff over black for Python formatting.",
       category="preference", importance=4,
       entities=["gitricko"], tags=["formatting", "python"]
     )

User: "Remember the project uses Python 3.13"
  → Respond
  → Direct: mnemon_remember(
       text="Project uses Python 3.13.",
       category="fact", importance=4,
       entities=["gitricko"], tags=["python", "project-setup"]
     )

User: "Also save these three things: ..."
  → Respond
  → Delegate: bulk save via subagent (3+ items)
```

## Pitfalls

### `mnemon_remember` IS a Real Tool (Plugin-Exposed)

The function `mnemon_remember(...)` is a real Hermes tool, exposed by the `gitricko/hermes-plugin-mnemon` plugin. Call it directly from your toolset — no CLI needed.

Subagents may NOT inherit plugin-defined tools. If delegating a save, pass `mnemon remember` CLI commands in context and set `toolsets=["terminal"]` so the subagent runs via shell.

### Don't Confuse `mnemon_remember` with `memory()`

| Tool | Target | Purpose |
|------|--------|---------|
| `mnemon_remember()` | Mnemon graph DB | Durable, queriable, multi-session |
| `memory()` | Agent memory | Injected every turn, bounded at 2.2K chars |

They target different stores. Use `mnemon_remember()` for Mnemon entries and `memory()` for the Hermes built-in memory.

## Related

- **Skill**: `.devcontainer/skills/memory-automation/` — Procedural how-to
- **Skill**: `.devcontainer/skills/mnemon-seed-persistence/` — Durable seed.json persistence
- **Wiki**: [mnemon-seed-persistence.md](mnemon-seed-persistence.md) — Seed persistence details
- **Wiki**: [persistent-memory-proposal.md](persistent-memory-proposal.md) — Architecture decision for Hermes MEMORY.md/USER.md