# Mnemon Seed Persistence Across Codespace Rebuilds

## Overview

**CRITICAL**: The **live Mnemon DB is ephemeral**. Each fresh Codespace spawn re-seeds from the checked-in JSON file `.devcontainer/mnemon/seed.json`, imported by `start-hermes.sh` on every boot.

`mnemon_remember` writes only land in `~/.mnemon/data/default/mnemon.db` for THIS instance — they do NOT survive a container rebuild. To make a memory or skill available to a *future* fresh Codespace, it must be in `seed.json` (and committed), not just the live DB.

## Seed.json Format & Contract

```json
{
  "schema_version": "1",
  "insights": [
    {
      "content": "Lead with the salient fact; plain text, no headers.",
      "category": "context",     // preference|decision|insight|fact|context|general
      "importance": 5,            // 1–5
      "tags": ["codespace","cdp"],
      "entities": [],
      "source": "agent"
    }
  ]
}
```

- **Import deduplicates by content prefix** — same content won't be imported twice
- `check-seed-export.sh` flags any live Mnemon entry with importance ≥ 4 missing from seed.json (action-needed before merge)

## Workflow (When Committing a Skill or Durable Insight)

### 1. Propose the Entry for User Review

**Do NOT blind auto-commit** — user wants sign-off on durable memory.

### 2. Edit `.devcontainer/mnemon/seed.json`

Append to the `insights` array.

### 3. Also Commit a Standalone Extract

Commit a standalone `seed-<topic>.json` (same schema, just the new insights) into the same PR, so the memory ships with the code that needs it.

### 4. Validate Before Commit

The exact step `start-hermes.sh` runs:
```bash
mnemon import --dry-run .devcontainer/mnemon/seed.json
```
Expect: `"Dry run: N insights, 0 explicit edges — validation passed."`

### 5. Commit and Push

Commit with `--no-gpg-sign` (GPG unavailable; plain `git commit` exits 128). Push with the VS Code server token:

```bash
git -c credential.helper= -c "url.https://gitricko:${GH_TOKEN}@github.com/.insteadOf=https://github.com/" push origin <branch>
```

## Live Tool Still Matters

Use `mnemon_remember`/`mnemon_recall` during the session for immediate recall and for staging what should later be promoted to seed.json.

- **Live DB** = working set
- **seed.json** = durable snapshot

## Related

- **Skill**: `.devcontainer/skills/mnemon-seed-persistence/` — Procedural how-to
- **Skill**: `.devcontainer/skills/memory-automation/` — Live Mnemon workflow
- **Wiki**: [memory-automation.md](memory-automation.md) — Live workflow details
- **Wiki**: [persistent-memory-proposal.md](persistent-memory-proposal.md) — Architecture decision for Hermes MEMORY.md/USER.md