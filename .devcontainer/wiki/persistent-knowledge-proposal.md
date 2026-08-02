# Proposal: Persistent Knowledge System for Hermes-CodeSpace

> **Status**: COMPLETE — All 3 phases implemented and CI passing
> **Date**: 2026-08-01 (revised 2026-08-02)
> **Goal**: Make Hermes Agent knowledge persist across Codespace sessions via Git
> **Key change from v1→v2**: Replaced rsync/cp with symlinks
> **Key change from v2→v3**: Renamed "knowledge" to "wiki"; resolved all open questions
> **Key change from v3→final**: Added Mnemon seeding (Phase 3), unified dependency validation

---

## The Problem

Hermes Agent is temporal — each Codespace session starts fresh. Knowledge learned in session N (skills discovered, workarounds found, wiki-worthy insights) is lost when the Codespace is rebuilt. The user wants a system where:

1. Hermes can create new skills and knowledge during a session
2. That knowledge persists via Git (committed to the repo)
3. On next Codespace boot, Hermes automatically has access to the new knowledge
4. The user reviews and approves what gets committed (via `git diff`)

---

## The Core Insight

**Git IS the persistence layer.** Everything in the repo survives across sessions. The startup scripts already copy templates from `.devcontainer/` to `~/.hermes/`. We just need to extend this pattern — using **symlinks** so that writes to `~/.hermes/` land in the git-tracked workspace.

---

## Key Design Decision: Symlinks, Not rsync

| Approach | Problem |
|----------|---------|
| `rsync` / `cp` from workspace to `~/.hermes/` | Changes to `~/.hermes/skills/` are lost — only in the ephemeral copy, git never sees them |
| **Symlink**: `~/.hermes/skills/codespace` → `.devcontainer/skills/` | Writes to `~/.hermes/skills/codespace/` land directly in the workspace. Git sees everything. One source of truth. |

Why symlinks win:
- Hermes writes a new skill → it appears in `git status` immediately
- User reviews via `git diff`, decides to commit
- Next boot: committed skill is available automatically
- No copy/sync step needed — the symlink IS the sync

---

## Proposed Repository Structure

```
hermes-codespace/
├── .devcontainer/
│   ├── skills/                       # Codebase-specific skills (git-tracked)
│   │   ├── memory-automation/
│   │   │   └── SKILL.md              # Migrated from skill-memory-automation.md
│   │   ├── codespace-gh-auth/
│   │   │   └── SKILL.md
│   │   └── ...future skills...
│   ├── wiki/                         # LM Wiki — reference articles (git-tracked)
│   │   ├── INDEX.md                  # Table of contents
│   │   ├── codespace-playbook.md     # Migrated from CODESPACE_PLAYBOOK.md
│   │   ├── repository-analysis.md    # Migrated from REPOSITORY_ANALYSIS.md
│   │   ├── github-actions-testing-plan.md
│   │   ├── persistent-knowledge-proposal.md  # This document
│   │   └── ...future articles...
│   ├── mnemon/                       # Mnemon seed data (git-tracked)
│   │   ├── seed.json                 # Curated knowledge catalog (wiki pointers,
│   │   │                             #   key decisions, architecture facts)
│   │   └── validate-seed.py          # CI validation script
│   ├── start-hermes.sh               # Boot script: dependency validation,
│   │                                 #   service startup, symlink, Mnemon import
│   ├── post-create-cmd.sh            # First-create setup (npm, hermes install)
│   └── ...existing files...
├── README.md
└── .github/workflows/devcontainer-ci.yml  # Path-filtered multi-job CI
```

**Why `.devcontainer/` not `.hermes/` in the repo root:**
- `.devcontainer/` is the standard path — always present, stable naming
- Avoids confusion with Hermes runtime dirs (`~/.hermes/`)
- User's future projects caan use and put files at their own git root for their own purposes
- Project specific knowledge stays/persistence in git, particularly in .devcontainer subfolder (`skills`, `wiki`)

**Naming: "wiki" not "knowledge"** — follows the Karpathy LM Wiki concept. The wiki articles inside follow LM Wiki conventions (interlinked markdown articles, cross-references). The content inside the folder IS the LM Wiki; the folder name "wiki" is universally understood.

---

## How Each Layer Works

### Layer 1: Skills (via symlink)

**Current state**: Skills live in `~/.hermes/skills/` (ephemeral). One skill (`memory-automation`) is manually copied from `.devcontainer/skill-memory-automation.md`.

**Proposed**: Skills live in `.devcontainer/skills/<name>/SKILL.md` (git-tracked). On every start, `start-hermes.sh` creates a symlink:

```
~/.hermes/skills/codespace → /workspaces/hermes-codespace/.devcontainer/skills/
```

This means:
- Bundled Hermes skills (`apple/`, `creative/`, `github/`, etc.) stay untouched at `~/.hermes/skills/`
- Codebase-specific skills appear under `~/.hermes/skills/codespace/<name>/`
- Hermes can `skill_view(name='codespace/memory-automation')` — works naturally
- When Hermes creates a new skill, it writes to the symlinked path — lands in workspace — git sees it

**Hermes workflow for creating a new skill**:
1. Discovers something worth persisting
2. Writes SKILL.md to `.devcontainer/skills/<name>/SKILL.md` (via symlink)
3. File is UNCOMMITTED — visible in `git status`
4. User reviews via `git diff`, decides to commit or discard
5. Next Codespace boot: skill is available immediately (already in repo)

### Skill Discovery: Runtime Auto-Detection

Hermes discovers skills **automatically at runtime** — no restart needed:

- `iter_skill_index_files()` uses `os.walk(followlinks=True)` with NO depth limit
- Symlinks are explicitly followed (the source code has a comment confirming this is intentional for our exact use case)
- The skill scan has a **30-second cache TTL** — directory mtime changes invalidate the cache
- New skills appear in `skill_list` and `skill_view()` within ~30 seconds of creation
- The system prompt index (available_skills) updates each conversation turn

**Practical implication**: When Hermes (or the user) creates a skill at `.devcontainer/skills/new-thing/SKILL.md`, the symlink makes it visible at `~/.hermes/skills/codespace/new-thing/`, and Hermes can discover and load it on the next tool call. No manual registration needed.

### Layer 2: Wiki Base (`.devcontainer/wiki/`)

A unified wiki directory containing reference articles, reference docs, and
any persistent reference material. Skills handle "how to do X" procedures;
the wiki handles "how system Y works" reference material. This follows
the LM Wiki concept — interlinked markdown articles forming a knowledge
base that the agent can read directly.

**Structure**:
```markdown
# .devcontainer/wiki/codespace-auth.md
---
title: GitHub Codespace Authentication
tags: [github, codespace, auth, tokens]
created: 2026-08-01
---

## The Problem
In a Codespace, the real GITHUB_TOKEN is in the VS Code server process...

## The Solution
Extract via /proc/PID/environ...

## Pitfalls
- Do NOT use GITHUB_CODESPACE_TOKEN...
```

**How Hermes accesses wiki articles**:
- No symlink needed — wiki is read-only reference material
- Agent is instructed (via `.hermes.md` or skill) to read from `.devcontainer/wiki/`
- `.devcontainer/wiki/INDEX.md` serves as table of contents
- Articles are read via `read_file()` directly from the workspace path

**When to create a wiki article vs a skill**:
- Skill = procedural knowledge ("how to do X") → `.devcontainer/skills/`
- Wiki article = reference knowledge ("how system Y works") → `.devcontainer/wiki/`
- Insight/fact = single line → Mnemon (not committed to git)

### Layer 3: Mnemon Pre-seeding ✅ COMPLETE

On every Codespace boot, `start-hermes.sh` imports curated wiki article
summaries and key decisions into Mnemon so that `mnemon_recall()` can
surface relevant articles without the agent knowing about them in advance.

**Seed file**: `.devcontainer/mnemon/seed.json` (git-tracked)
- 14 curated insights: wiki pointers, key decisions, architecture facts
- All entries importance >= 4 (high-signal, low-noise)
- Maintained via agent proposals → user review → git commit

**Boot flow**:
1. Dry-run validation (ensures JSON is well-formed)
2. Real import (Mnemon handles deduplication automatically)
3. Parse output (imported/skipped/errors counts logged)

**CI validation**: `validate-seed.py` checks schema, fields, categories,
importance range, and enforces < 50 entry size guard.

**Key insight**: Mnemon stores POINTERS/summaries, wiki dir stores
FULL content. This way:
- Mnemon stays small and fast (pointers only)
- Full content is always in git (durable)
- No need to dump large articles into the graph DB

---

## Changes to Existing Files

### `start-hermes.sh` — complete refactoring:

The boot script was refactored to add unified dependency validation,
Mnemon seed import, and simplified service startup:

```bash
#!/bin/bash
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE:-$(dirname "$SCRIPT_DIR")}"

# ── Validate ALL critical dependencies ──────────────────────────────
MISSING=()
for bin in modelrelay omniroute ollama hermes mnemon; do
  if ! command -v "$bin" &>/dev/null; then
    MISSING+=("binary: $bin")
  fi
done
if [ ! -d "$WORKSPACE_ROOT/.devcontainer/skills" ]; then
  MISSING+=("directory: .devcontainer/skills/")
fi
if [ ! -f "$WORKSPACE_ROOT/.devcontainer/mnemon/seed.json" ]; then
  MISSING+=("file: .devcontainer/mnemon/seed.json")
fi
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "FATAL: Missing critical dependencies:"
  for item in "${MISSING[@]}"; do echo "  - $item"; done
  exit 1
fi

# ── Start services (pgrep only — binaries guaranteed by validation) ──
if pgrep -f modelrelay > /dev/null; then
  echo "modelrelay already running, skipping"
else
  setsid /usr/local/bin/modelrelay >> /tmp/modelrelay.log 2>&1 &
fi
# ... (same pattern for omniroute, ollama, hermes-gateway, hermes-dashboard)

# ── Create skills symlink ───────────────────────────────────────────
SKILLS_SYMLINK="$HOME/.hermes/skills/codespace"
SKILLS_TARGET="$WORKSPACE_ROOT/.devcontainer/skills"
if [ ! -L "$SKILLS_SYMLINK" ]; then
    ln -s "$SKILLS_TARGET" "$SKILLS_SYMLINK"
fi

# ── Import Mnemon seed data ─────────────────────────────────────────
SEED_FILE="$WORKSPACE_ROOT/.devcontainer/mnemon/seed.json"
if mnemon import --dry-run "$SEED_FILE" 2>&1 | grep -q "validation passed"; then
  mnemon import "$SEED_FILE"
fi
```

**Why `start-hermes.sh` (not `post-create-cmd.sh`)?**
- `start-hermes.sh` runs on EVERY start — handles Codespace rebuilds
- `post-create-cmd.sh` runs once on first creation only
- If the Codespace is rebuilt but `.devcontainer/` survives, we still need the symlink
- Safer: always idempotent, always checks

**Why no `rm -rf`?**
- Boot script just checks: does symlink exist? If not, create it.
- If it exists and points to the right place, do nothing.
- If it's broken (pointing to a deleted path), recreate it.

### `.hermes.md` additions (agent instructions):

```markdown
## Knowledge Persistence

### Creating skills
When you discover something worth saving:
1. Create a skill at .devcontainer/skills/<name>/SKILL.md
   (or via symlink: ~/.hermes/skills/codespace/<name>/SKILL.md)
2. File is uncommitted — visible in `git status`
3. User reviews and decides to commit

### Accessing reference knowledge
Read wiki articles and reference docs from:
  /workspaces/hermes-codespace/.devcontainer/wiki/
Check INDEX.md for available articles.

### Creating wiki articles
When you learn reference knowledge:
1. Create article at .devcontainer/wiki/<topic>.md
2. Update .devcontainer/wiki/INDEX.md
```

---

## The Flow (End-to-End)

```
Session N:
  1. Boot → start-hermes.sh creates symlink:
       ~/.hermes/skills/codespace → .devcontainer/skills/
  2. Hermes loads, bundled skills + codespace skills both available
  3. User interacts, Hermes discovers something
  4. Hermes writes skill to .devcontainer/skills/<name>/SKILL.md (via symlink)
  5. File is uncommitted — visible in git status
  6. User sees in git diff, reviews, commits + pushes

Session N+1 (new Codespace):
  1. Clone/pull repo → .devcontainer/skills/ has the new skill
  2. start-hermes.sh creates symlink on boot
  3. Hermes can immediately skill_view(name='codespace/<name>')
  4. Knowledge is available without re-discovery
```

---

## Finalized Decisions

These questions were discussed and resolved across three sessions:

### Q1: Where do CODESPACE_PLAYBOOK.md and REPOSITORY_ANALYSIS.md go?
**DECISION**: Move into `.devcontainer/wiki/` as wiki articles.
They are reference knowledge ("how system Y works"), not procedures.

### Q2: How aggressive should knowledge capture be?
**DECISION**: Both proactive AND user-triggered.
- Hermes can proactively capture knowledge during sessions
- User can also explicitly request knowledge capture
- The git review loop (git diff) is the safety net — everything
  lands uncommitted, user decides what to keep

### Q3: Should there be a skill_view helper for codespace skills?
**DECISION**: Skip it. Not needed.
- The symlink at `~/.hermes/skills/codespace/` naturally namespaces
  codespace skills without conflicting with bundled ones
- Hermes already has `skills_list` and `skill_view` — they work
  with the symlinked path via `followlinks=True`

### Q4: How to handle skill versioning if two Codespaces diverge?
**DECISION**: Leave to Git.
- Developers use standard git merge/conflict resolution
- It's a deliberate process by the developer — they decide which
  skill changes are more important
- No system-level versioning solution needed

### Q5: Boot script for symlink creation?
**DECISION**: `start-hermes.sh` (not `post-create-cmd.sh`).
- Runs on every start, handles rebuilds
- Idempotent: check if exists, create if not, skip if already there
- No destructive `rm -rf` needed

### Q6: Why wiki and not a symlink?
**DECISION**: Wiki articles are read-only reference material.
- Agent reads from `.devcontainer/wiki/` directly via `read_file()`
- No symlink needed — the agent is instructed where to find them
- Skills need the symlink because Hermes WRITES to `~/.hermes/skills/`

---

## Implementation Plan

### Phase 1: Skills Layer ✅ COMPLETE
1. Create `.devcontainer/skills/` directory in repo
2. Migrate `skill-memory-automation.md` → `.devcontainer/skills/memory-automation/SKILL.md`
3. Remove old `skill-memory-automation.md` from `.devcontainer/`
4. Add symlink creation logic to `start-hermes.sh`
5. Update `.hermes.md` with knowledge persistence instructions
6. Test: verify symlink created, existing memory-automation skill accessible

### Phase 2: Wiki Base ✅ COMPLETE
1. Create `.devcontainer/wiki/` directory with INDEX.md
2. Migrate CODESPACE_PLAYBOOK.md → `wiki/codespace-playbook.md`
3. Migrate REPOSITORY_ANALYSIS.md → `wiki/repository-analysis.md`
4. Migrate GITHUB_ACTIONS_TESTING_PLAN.md → `wiki/github-actions-testing-plan.md`
5. Migrate PERSISTENT_KNOWLEDGE_PROPOSAL.md → `wiki/persistent-knowledge-proposal.md`
6. Remove old root-level .md files (only README.md remains)
7. Add path-filtered CI with dorny/paths-filter@v3 (3 jobs: detect, build, lint)
8. CI validates: markdownlint, SKILL.md structure, wiki INDEX consistency, seed.json

### Phase 3: Mnemon Seeding ✅ COMPLETE
1. Create `.devcontainer/mnemon/seed.json` — curated knowledge catalog (14 entries)
   - 4 wiki pointers (importance 4)
   - 4 key decisions (importance 5)
   - 4 architecture facts (importance 4)
   - 2 CI debugging insights (importance 4)
2. Create `.devcontainer/mnemon/validate-seed.py` — CI validation script
3. Add boot import to `start-hermes.sh`:
   - Dry-run validation → real import → parse output
   - Mnemon deduplication handles duplicates automatically
4. Add unified dependency validation:
   - Checks 5 binaries (modelrelay, omniroute, ollama, hermes, mnemon)
   - Checks skills directory and seed.json
   - Fails fast with clear FATAL message if any dependency missing
5. Simplified service sections (pgrep only, no command-v fallbacks)
6. CI validates seed.json structure (schema, fields, categories, size guard)

### Ongoing: Knowledge Capture Workflow
- Agent proposes new entries for seed.json when creating skills/wiki articles
- User reviews via `git diff`, approves/rejects, commits when ready
- Seed file stays lean (< 50 entries) — consolidate or move to session memory

---

## Hermes Skill Folder Structure (Reference)

Hermes uses `os.walk(followlinks=True)` to discover skills at any depth.
The folder structure is purely organizational — categories (e.g. `creative/`,
`research/`) group skills visually in the system prompt and autocomplete but
have zero functional impact on loading or execution.

Example bundled skills:
- `skills/apple/notes/SKILL.md`          (depth 2)
- `skills/research/arxiv/SKILL.md`       (depth 2)
- `skills/autonomous-ai-agents/hermes-agent/SKILL.md`  (depth 2)
- `skills/memory-automation/SKILL.md`    (depth 1)

Our codespace skills at depth 1 (e.g. `codespace/memory-automation/SKILL.md`)
work exactly the same. We can add categories later if we want.

---

*This proposal was created 2026-08-01, revised through multiple sessions
on 2026-08-02. All three phases implemented and CI passing. PR #22 ready
to merge.*
