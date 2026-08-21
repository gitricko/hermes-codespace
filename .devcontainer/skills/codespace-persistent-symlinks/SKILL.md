---
name: codespace-persistent-symlinks
description: "Persist Hermes state across Codespace rebuilds via symlinks."
---

# Persisting Hermes runtime state via symlinks (Codespace)

Hermes knowledge/memory (`~/.hermes/memories/MEMORY.md`, `USER.md`) and skills die on
Codespace rebuild unless persisted. The durable technique mirrors how the repo already
persists skills: a **whole-folder symlink** from runtime to a git-tracked repo dir.

## The validated pattern

```
runtime:  ~/.hermes/memories            (a symlink → the tracked folder)
target:   .devcontainer/memories/       (git-tracked: MEMORY.md, USER.md, .gitignore)
.gitignore:  *.lock  *.log              (Hermes writes lock/log beside the memories)
```

- Whole-folder symlink (skills-style) is the default: single point of truth,
  no copy-back between `~/.hermes` and the repo, edits flow both ways instantly.
  Use per-file symlinks only for mixed-state runtime dirs (see below) — never as a
  general substitute for the whole-folder pattern.
- Hermes memory writes are symlink-safe: `atomic_replace` (utils.py) re-solves the
  symlink and writes the real git file — no Hermes change needed.
- Memory path is `~/.hermes/memories/`, NOT `profiles/default/memories/`.

## Per-file symlink exception (mixed-state runtime dirs)

The whole-folder rule assumes the runtime dir holds ONLY durable, persistable
state. Some tools keep durable config in a dir that also holds private/runtime
state (e.g. `~/.pi/agent/` mixes `models.json`/`settings.json` with `auth.json`,
`sessions/`, lock files). Symlinking the whole folder would persist secrets and
ephemeral state into the repo — wrong. Instead:

1. Track ONLY the durable config files under `.devcontainer/<name>/`
   (e.g. `.devcontainer/pi-config/models.json`, `settings.json`).
2. Replace each runtime file with a symlink to the tracked copy:
   `ln -sf "$TRACKED/$f" "$RUNTIME/$f"` — replace a plain file, but never clobber
   an existing symlink that already resolves to the target.
3. Add an idempotent guard in `start-hermes.sh` (repair-guard style) that re-links
   them on every boot, because the tool writes its own stub on first launch:
   `if [ "$(readlink -f "$runtime")" != "$(readlink -f "$tracked")" ]; then rm -f "$runtime"; ln -s "$tracked" "$runtime"; fi`

This keeps secrets/ephemeral state out of git while surviving rebuilds.

## Placement decision (Option A — validated 2026-08)

Two layers, keep `start-hermes.sh` trivial:

1. **Authoritative = `post-create-cmd.sh`** (`postCreateCommand`, runs once on a FRESH
   container). Create the symlink right after Hermes is installed, before Hermes first
   instantiates `~/.hermes/memories`. Cleanest moment — nothing to migrate.
2. **Repair guard = `start-hermes.sh`** — keep under ~12 lines. `postCreateCommand`
   never re-runs on later boots or on containers created before the feature shipped,
   so a guard (`if [ "$(readlink runtime)" != "$target" ]; then ln -s ...`) catches
   them. Handle 3 cases: already-correct link (no-op), real dir (repair via
   `rm -rf` + `ln -s`), missing entirely (just link).

Do NOT port a first-run migration/seed block into start-hermes.sh. If the tracked files
are committed, that code is dead weight and reads as convoluted.

## Verification (automated)

`self-check.sh` asserts both symlinks in its `Persistence` section (section 9), so CI
fails loudly if either drifts:

- `~/.hermes/memories` → `$REPO_ROOT/.devcontainer/memories`
- `~/.hermes/skills/codespace` → `$REPO_ROOT/.devcontainer/skills`

Handles 3 cases per link: correct symlink (ok), real dir (fail), missing (fail), plus
checks tracked MEMORY.md / USER.md / SKILL.md exist. To enforce it, the CI
`detect-changes` path filter lists `.devcontainer/memories/**` and `.devcontainer/skills/**`
under `infrastructure`, so persistence changes trigger `full-build` (which runs
self-check.sh). Run locally:
`HERMES_WEBTOP_SKIP_CHECKS=services,models,disk,cron,ollama,memory bash .devcontainer/self-check.sh`

## Pitfalls

- **Removing a seed block can silently lose a behavioral nudge.** Before deleting a
  start-hermes.sh seed that writes USER.md, fold its content into the tracked USER.md
  first so the rule survives (the "use Mnemon as primary memory provider" nudge was
  preserved this way).
- **Undo-by-`head -n -1` corrupts memory files.** When testing write-through, remove
  ONLY the injected marker line (perl/grep), never tail-trim — you can truncate a real
  directive and the file shrinks unexpectedly (observed 1297B → 504B).
- Verify the guard against ALL THREE cases, not just the happy path.
- **Mixed-state runtime dirs need per-file symlinks, not whole-folder.** `~/.pi/agent/`
  is the canonical case: symlink only `models.json`/`settings.json` into
  `.devcontainer/pi-config/`; never symlink the whole dir (it drags in `auth.json`,
  `sessions/`, locks). Add a `start-hermes.sh` guard to re-link past the tool's own
  first-launch stub, and verify the guard replaces a plain stub with the symlink.

## Sync note (wiki)
- `persistent-memory-proposal.md` — reference/proposal doc vs this procedural skill.
  Keep the Option-A split and the self-check wiring (below) mirrored in both.

## Cleanup
When deleting a skill/project, also purge its persisted files and cross-references:
- [persistent-knowledge/references/cleanup-deleted-skill.md](../persistent-knowledge/references/cleanup-deleted-skill.md) — Full procedure for wiki, Mnemon DB, seed.json, skills, and cross-references