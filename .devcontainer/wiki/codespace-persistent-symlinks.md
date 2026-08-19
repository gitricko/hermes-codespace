# Persistent Symlinks for Hermes State in Codespaces

## Overview

Hermes knowledge/memory (`~/.hermes/memories/MEMORY.md`, `USER.md`) and skills die on Codespace rebuild unless persisted. The durable technique mirrors how the repo already persists skills: a **whole-folder symlink** from runtime to a git-tracked repo directory.

This article documents the reference architecture for persisting Hermes runtime state across Codespace rebuilds using whole-folder symlinks.

## The Validated Pattern

```
runtime:  ~/.hermes/memories            (a symlink → the tracked folder)
target:   .devcontainer/memories/       (git-tracked: MEMORY.md, USER.md, .gitignore)
.gitignore:  *.lock  *.log              (Hermes writes lock/log beside the memories)

runtime:  ~/.hermes/skills/codespace    (a symlink → the tracked folder)
target:   .devcontainer/skills/         (git-tracked: all skills)
```

### Key Principles

1. **Whole-folder symlink (skills-style), NOT per-file links** — single point of truth, no copy-back between `~/.hermes` and the repo, edits flow both ways instantly.

2. **Hermes memory writes are symlink-safe** — `atomic_replace` (utils.py) re-solves the symlink and writes the real git file — no Hermes change needed.

3. **Memory path is `~/.hermes/memories/`, NOT `profiles/default/memories/`** — this is the canonical path Hermes uses.

## Placement Decision: Option A (Validated 2026-08)

Two layers, keep `start-hermes.sh` trivial:

### Layer 1: Authoritative = `post-create-cmd.sh`

Runs once on a FRESH container (via `postCreateCommand`). Creates the symlink right after Hermes is installed, before Hermes first instantiates `~/.hermes/memories`. Cleanest moment — nothing to migrate.

```bash
# In post-create-cmd.sh
# Create memories symlink
if [ ! -L ~/.hermes/memories ]; then
  rm -rf ~/.hermes/memories
  ln -s "$REPO_ROOT/.devcontainer/memories" ~/.hermes/memories
fi

# Create skills symlink
if [ ! -L ~/.hermes/skills/codespace ]; then
  rm -rf ~/.hermes/skills/codespace
  ln -s "$REPO_ROOT/.devcontainer/skills" ~/.hermes/skills/codespace
fi
```

### Layer 2: Repair Guard = `start-hermes.sh`

Keep under ~12 lines. `postCreateCommand` never re-runs on later boots or on containers created before the feature shipped, so a guard catches them:

```bash
# In start-hermes.sh
# Repair memories symlink
TARGET_MEM="$REPO_ROOT/.devcontainer/memories"
if [ "$(readlink ~/.hermes/memories)" != "$TARGET_MEM" ]; then
  rm -rf ~/.hermes/memories
  ln -s "$TARGET_MEM" ~/.hermes/memories
fi

# Repair skills symlink
TARGET_SKILLS="$REPO_ROOT/.devcontainer/skills"
if [ "$(readlink ~/.hermes/skills/codespace)" != "$TARGET_SKILLS" ]; then
  rm -rf ~/.hermes/skills/codespace
  ln -s "$TARGET_SKILLS" ~/.hermes/skills/codespace
fi
```

**Handles 3 cases per link:**
- Already-correct symlink → no-op
- Real directory → repair via `rm -rf` + `ln -s`
- Missing entirely → just link

**Do NOT** port a first-run migration/seed block into `start-hermes.sh`. If the tracked files are committed, that code is dead weight and reads as convoluted.

## Verification (Automated)

`self-check.sh` asserts both symlinks in its `Persistence` section (section 9), so CI fails loudly if either drifts:

- `~/.hermes/memories` → `$REPO_ROOT/.devcontainer/memories`
- `~/.hermes/skills/codespace` → `$REPO_ROOT/.devcontainer/skills`

Handles 3 cases per link: correct symlink (ok), real dir (fail), missing (fail), plus checks tracked MEMORY.md / USER.md / SKILL.md exist.

CI wiring: The `detect-changes` path filter lists `.devcontainer/memories/**` and `.devcontainer/skills/**` under `infrastructure`, so persistence changes trigger `full-build` (which runs self-check.sh).

Run locally:
```bash
HERMES_WEBTOP_SKIP_CHECKS=services,models,disk,cron,ollama,memory bash .devcontainer/self-check.sh
```

## Pitfalls Reference

| Pitfall | Description | Prevention |
|---------|-------------|------------|
| **Removing seed block loses behavioral nudges** | Before deleting a start-hermes.sh seed that writes USER.md, fold its content into tracked USER.md first | Always migrate seed content to tracked files before removing seed code |
| **Undo-by-`head -n -1` corrupts memory files** | When testing write-through, remove ONLY the injected marker line (perl/grep), never tail-trim | Use precise line removal, never `head -n -1` |
| **Guard not tested against all 3 cases** | Verify the guard against: correct link, real dir, missing | Test all three cases in CI/local |

## Sync Note (Wiki ↔ Skill)

- `persistent-memory-proposal.md` — reference/proposal doc vs this procedural skill
- Keep the Option-A split and the self-check wiring mirrored in both

## Related

- **Skill**: `.devcontainer/skills/codespace-persistent-symlinks/` — Procedural how-to
- **Wiki**: [persistent-memory-proposal.md](persistent-memory-proposal.md) — Architecture decision document
- **Wiki**: [persistent-knowledge-proposal.md](persistent-knowledge-proposal.md) — Broader knowledge persistence architecture
- **Skill**: `.devcontainer/skills/mnemon-seed-persistence/` — Mnemon seed.json persistence
- **Skill**: `.devcontainer/skills/persistent-knowledge/` — Knowledge persistence pattern