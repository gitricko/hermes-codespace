# Persistent Knowledge Management in Codespaces

## Overview

This article documents the reference architecture for persisting skills and knowledge in GitHub Codespaces via whole-folder symlinks. This pattern ensures that Hermes skills, memories, and other runtime state survive Codespace rebuilds.

## The Validated Pattern

The repo uses **whole-folder symlinks** (not per-file links) from runtime locations to git-tracked repo directories:

```
~/.hermes/skills/codespace  →  .devcontainer/skills/     (git-tracked)
~/.hermes/memories/         →  .devcontainer/memories/   (git-tracked)
```

### Key Principles

1. **Single point of truth** — No copy-back between `~/.hermes` and the repo; edits flow both ways instantly
2. **Symlink-safe writes** — Hermes `atomic_replace` re-solves symlinks and writes the real git file
3. **Git-tracked content** — All skills, MEMORY.md, USER.md, seed.json live in `.devcontainer/` and are committed

## Symlink Creation

### Authoritative: `post-create-cmd.sh` (Runs Once on Fresh Container)

```bash
# Skills symlink
if [ ! -L ~/.hermes/skills/codespace ]; then
  rm -rf ~/.hermes/skills/codespace
  ln -s "$REPO_ROOT/.devcontainer/skills" ~/.hermes/skills/codespace
fi

# Memories symlink
if [ ! -L ~/.hermes/memories ]; then
  rm -rf ~/.hermes/memories
  ln -s "$REPO_ROOT/.devcontainer/memories" ~/.hermes/memories
fi
```

### Repair Guard: `start-hermes.sh` (Runs Every Boot)

```bash
# Skills
TARGET_SKILLS="$REPO_ROOT/.devcontainer/skills"
if [ "$(readlink ~/.hermes/skills/codespace)" != "$TARGET_SKILLS" ]; then
  rm -rf ~/.hermes/skills/codespace
  ln -s "$TARGET_SKILLS" ~/.hermes/skills/codespace
fi

# Memories
TARGET_MEM="$REPO_ROOT/.devcontainer/memories"
if [ "$(readlink ~/.hermes/memories)" != "$TARGET_MEM" ]; then
  rm -rf ~/.hermes/memories
  ln -s "$TARGET_MEM" ~/.hermes/memories
fi
```

Handles 3 cases: correct symlink (no-op), real dir (repair), missing (link).

## Self-Check Verification (Automated)

`self-check.sh` asserts both symlinks in its `Persistence` section (section 9):

- `~/.hermes/memories` → `$REPO_ROOT/.devcontainer/memories`
- `~/.hermes/skills/codespace` → `$REPO_ROOT/.devcontainer/skills`

Checks 3 cases per link: correct symlink (ok), real dir (fail), missing (fail), plus tracked MEMORY.md / USER.md / SKILL.md exist.

CI integration: Path filter lists `.devcontainer/memories/**` and `.devcontainer/skills/**` under `infrastructure` → triggers `full-build` (runs self-check.sh).

## CI Path Filter

| Path | Category | CI Trigger |
|------|----------|------------|
| `.devcontainer/memories/**` | infrastructure | full-build |
| `.devcontainer/skills/**` | infrastructure | full-build |
| `.devcontainer/memories/**` (content only) | runtime | lint-check (30s) |
| `.devcontainer/skills/**` (content only) | runtime | lint-check (30s) |

Content changes to skills/memories trigger fast lint-check; infrastructure changes (boot scripts, devcontainer.json, workflows) trigger full-build.

## Mnemon Seed Persistence

Live Mnemon DB is ephemeral — re-seeded from `.devcontainer/mnemon/seed.json` on every boot via `start-hermes.sh`.

To persist across rebuilds:
1. Promote high-value insights (importance ≥ 4) to `seed.json`
2. Validate: `mnemon import --dry-run .devcontainer/mnemon/seed.json`
3. Commit seed.json (and standalone `seed-<topic>.json` extract)

## Skill Structure

Each skill in `.devcontainer/skills/<name>/` contains:
- `SKILL.md` — Procedural knowledge (YAML frontmatter + markdown)
- `scripts/` — Executable scripts
- `references/` — Reference documents
- `templates/` — Templates
- `requirements.txt` — Python dependencies (if any)

## Wiki Structure

Reference articles in `.devcontainer/wiki/`:
- `INDEX.md` — Table of contents
- `<topic>.md` — Reference knowledge (architecture, decisions, how systems work)
- Cross-linked with relative markdown links

## Relationship: Skill vs Wiki vs Mnemon

| Type | Location | Purpose |
|------|----------|---------|
| Skill | `.devcontainer/skills/` | Procedural: "how to do X" |
| Wiki | `.devcontainer/wiki/` | Reference: "how system Y works" |
| Mnemon | Live DB + `seed.json` | Insights: single facts, preferences, decisions |

## Related

- **Skill**: `.devcontainer/skills/persistent-knowledge/` — Procedural how-to
- **Skill**: `.devcontainer/skills/codespace-persistent-symlinks/` — Symlink pattern details
- **Skill**: `.devcontainer/skills/mnemon-seed-persistence/` — Seed persistence
- **Wiki**: [persistent-knowledge-proposal.md](persistent-knowledge-proposal.md) — Architecture decision document
- **Wiki**: [persistent-memory-proposal.md](persistent-memory-proposal.md) — MEMORY.md/USER.md versioning
- **Wiki**: [codespace-persistent-symlinks.md](codespace-persistent-symlinks.md) — Symlink pattern details
- **Wiki**: [mnemon-seed-persistence.md](mnemon-seed-persistence.md) — Seed persistence details