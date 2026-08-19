---
name: persistent-knowledge
description: "Persistent skills/knowledge in Codespace via symlinks."
---

# Persistent Knowledge Management

Symlink-based persistence for Hermes skills, wiki, and Mnemon across Codespace rebuilds.

## Architecture

- `~/.hermes/skills/codespace` → `.devcontainer/skills/` (symlink, whole folder)
- `~/.hermes/memories` → `.devcontainer/memories/` (symlink, whole folder)
- `.devcontainer/mnemon/seed.json` — checked-in snapshot for Mnemon re-seeding on fresh spawn

## Boot Workflow

`start-hermes.sh` (runs on every Codespace start/rebuild):
1. Creates symlinks if missing (idempotent)
2. Runs `mnemon import --dry-run .devcontainer/mnemon/seed.json` then real import
3. Validates symlinks via self-check.sh section 9

## CI Integration

Path-filtered CI (`.github/workflows/devcontainer-ci.yml`):
- `.devcontainer/skills/**` and `.devcontainer/memories/**` = **runtime** → lint-check only (~30s)
- Boot scripts, devcontainer.json, workflows = **infrastructure** → full-build (~15min)

## References

- [references/cleanup-deleted-skill.md](references/cleanup-deleted-skill.md) — Procedure for removing all traces of deleted skills/projects
