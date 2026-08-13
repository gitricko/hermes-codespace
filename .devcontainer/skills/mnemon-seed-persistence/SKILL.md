---
name: mnemon-seed-persistence
description: "Persist Mnemon memory across Codespace rebuilds."
version: 1.0.0
author: hermes-agent
license: MIT
tags:
  - mnemon
  - seed
  - persistence
  - codespace
  - memory
---

# Mnemon Seed Persistence (survive Codespace rebuilds)

CRITICAL: the **live Mnemon DB is ephemeral**. Each fresh Codespace spawn re-seeds from the
checked-in JSON file `.devcontainer/mnemon/seed.json`, imported by `start-hermes.sh` on every
boot. `mnemon_remember` writes only land in `~/.mnemon/data/default/mnemon.db` for THIS instance
— they do NOT survive a container rebuild. To make a memory or skill available to a *future* fresh
Codespace, it must be in `seed.json` (and committed), not just the live DB.

## Format & contract
```json
{ "schema_version": "1",
  "insights": [
    { "content": "Lead with the salient fact; plain text, no headers.",
      "category": "context",     // preference|decision|insight|fact|context|general
      "importance": 5,            // 1–5
      "tags": ["codespace","cdp"],
      "entities": ["cdp-browser-testing","lavish-axi"],
      "source": "agent" }
  ] }
```
Import deduplicates by content prefix. `check-seed-export.sh` flags any live Mnemon entry with
importance ≥ 4 missing from seed.json (action-needed before merge).

## Workflow (when committing a skill or durable insight)
1. **Propose** the entry for user review — do NOT blind auto-commit (user wants sign-off on durable memory).
2. **Edit** `.devcontainer/mnemon/seed.json` — append to the `insights` array.
3. **Also commit a standalone extract** `seed-<topic>.json` (same schema, just the new insights)
   into the same PR, so the memory ships with the code that needs it.
4. **Validate before commit** (the exact step `start-hermes.sh` runs):
   `mnemon import --dry-run .devcontainer/mnemon/seed.json`
   expect: "Dry run: N insights, 0 explicit edges — validation passed."
5. Commit with `--no-gpg-sign` (GPG unavailable; plain `git commit` exits 128). Push with the VS Code
   server token (see codespace-gh-auth):
   `git -c credential.helper= -c "url.https://gitricko:${GH_TOKEN}@github.com/.insteadOf=https://github.com/" push origin <branch>`

## Live tool still matters
Use `mnemon_remember`/`mnemon_recall` during the session for immediate recall and for staging what
should later be promoted to seed.json. Live DB = working set; seed.json = durable snapshot.

## Related
- codespace/memory-automation — the live Mnemon workflow this extends with durable persistence
- codespace/codespace-persistent-symlinks — whole-folder symlink persistence (memories/ + skills/)
