---
name: ci-lint-check
description: Run pre-commit CI lint validation locally before pushing to avoid GitHub Actions failures.
version: 0.1.0
author: gitricko, Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [ci, lint, pre-commit, github-actions, validation]
    related_skills: [codespace-persistent-symlinks, memory-automation]
---

# CI Lint Check Skill

Run the full CI lint validation locally before committing or creating a PR. This mirrors the `lint-check` job in `.github/workflows/devcontainer-ci.yml` and catches all format/validation issues that would fail CI.

## When to Use

- **Before every commit** that touches `.devcontainer/skills/**`, `.devcontainer/wiki/**`, `.devcontainer/mnemon/**`, `.devcontainer/memories/**`, or `.devcontainer/*.sh`
- **Before creating a PR** to ensure CI passes
- When CI fails and you need to debug locally

## Prerequisites

- `markdownlint-cli` (auto-installed by script)
- `python3` (for Mnemon seed validation)
- `bash` (for shell syntax checks)

## How to Run

```bash
# Quick one-liner (runs all checks):
bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh

# Or step by step:
bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh --markdown-only
bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh --skills-only
bash .devcontainer/skills/ci-lint_check.sh --wiki-only
bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh --mnemon-only
bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh --shell-only
bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh --symlink-only
```

## What It Validates

| Check | Files | CI Job |
|-------|-------|--------|
| Markdown lint | `.devcontainer/wiki/*.md`, `.devcontainer/skills/*/SKILL.md`, `.devcontainer/.hermes.md`, `README.md` | `lint-check` |
| SKILL.md structure | All skills in `.devcontainer/skills/*/SKILL.md` | `lint-check` |
| Wiki INDEX.md consistency | Every `.md` in wiki/ referenced in INDEX.md | `lint-check` |
| Mnemon seed.json | `.devcontainer/mnemon/seed.json` schema | `lint-check` |
| Root shell syntax | `.devcontainer/*.sh` | `lint-check` |
| Skill shell syntax | `.devcontainer/skills/*/scripts/*.sh` | `lint-check` |
| Symlink persistence | Tracked dirs + boot script symlink logic | `lint-check` |

## Procedure

### 1. Install dependencies (first run only)
```bash
npm install -g markdownlint-cli
```

### 2. Run full validation
```bash
bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh
```

### 3. Fix any reported issues
- Markdown lint: fix reported line/column issues
- SKILL.md: ensure YAML frontmatter with `name:` field
- Wiki: add missing articles to INDEX.md table
- Mnemon: `python3 .devcontainer/mnemon/validate-seed.py .devcontainer/mnemon/seed.json`
- Shell: `bash -n <script>` to see syntax errors
- Symlinks: ensure boot scripts create proper symlinks

### 4. Commit and push
```bash
git add -A
git commit -m "your message"
git push
```

## CI Behavior

| Changed Paths | CI Job | Duration |
|---------------|--------|----------|
| `.devcontainer/skills/**` | `lint-check` | ~30s |
| `.devcontainer/wiki/**` | `lint-check` | ~30s |
| `.devcontainer/mnemon/**` | `lint-check` | ~30s |
| `.devcontainer/memories/**` | `lint-check` | ~30s |
| `.devcontainer/*.sh` | `lint-check` | ~30s |
| `.github/workflows/**`, `devcontainer.json`, `post-create-cmd.sh`, `start-hermes.sh`, `self-check.sh` | `full-build` | ~15min |

**Only infrastructure changes trigger full-build.** Content changes (skills, wiki, mnemon, memories, shell scripts) run the fast lint-check only.

## Dev/Prod Parity Principle

**The local script IS the CI job.** The `lint-check` workflow step delegates entirely to `ci_lint_check.sh`:

```yaml
- name: Run local CI lint check script
  run: |
    npm install -g markdownlint-cli
    bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh
```

This guarantees identical validation in both environments. Never duplicate validation logic in CI YAML — the skill script is the single source of truth.

## Pitfalls

- **Don't skip this** — CI will fail and you'll waste time debugging in GitHub Actions
- **Run from repo root** — paths are relative to `/workspaces/hermes-codespace`
- **markdownlint config** is embedded in the script (matches CI config)
- **Mnemon seed validation** requires the validator script to exist
- **Symlink check** validates boot script logic, not actual runtime symlinks

## Integration with Git Hooks (Optional)

Add to `.git/hooks/pre-commit`:
```bash
#!/bin/bash
bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh || exit 1
```

## References

- `.github/workflows/devcontainer-ci.yml` — source of truth for CI jobs
- `.devcontainer/wiki/github-actions-testing-plan.md` — CI design doc
- `.devcontainer/skills/codespace-persistent-symlinks/SKILL.md` — symlink architecture

## Verification

```bash
# Should output "=== ALL CHECKS PASSED ==="
bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh
```

## For Future Agents

**MANDATORY**: Run this skill before ANY commit or PR that modifies:
- Skills (`.devcontainer/skills/**`)
- Wiki (`.devcontainer/wiki/**`)
- Mnemon (`.devcontainer/mnemon/**`)
- Memories (`.devcontainer/memories/**`)
- Devcontainer shell scripts (`.devcontainer/*.sh`)

```bash
# One command before commit:
bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh
```