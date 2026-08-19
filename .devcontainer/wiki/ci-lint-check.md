# CI Lint Check Skill

> **Reference**: Run pre-commit CI lint validation locally before pushing to avoid GitHub Actions failures.

## Overview

The `ci-lint-check` skill provides a local script that mirrors the `lint-check` job in `.github/workflows/devcontainer-ci.yml`. Running this before every commit/PR ensures CI passes without wasting time debugging in GitHub Actions.

## CI Job Classification

The CI workflow uses `dorny/paths-filter@v3` to classify changes:

| Category | Paths | CI Job | Duration |
|----------|-------|--------|----------|
| **infrastructure** | `.devcontainer/post-create-cmd.sh`, `.devcontainer/start-hermes.sh`, `.devcontainer/self-check.sh`, `.devcontainer/devcontainer.json`, `.github/workflows/**` | `full-build` | ~15min |
| **runtime** | `.devcontainer/skills/**`, `.devcontainer/wiki/**`, `.devcontainer/mnemon/**`, `.devcontainer/memories/**`, `.devcontainer/.hermes.md`, `.devcontainer/codespace-cleanup.sh` | `lint-check` | ~30s |
| **docs** | `README.md`, `*.md` (root) | `lint-check` | ~30s |

**Key insight**: Changes to skills, wiki, mnemon, memories, and devcontainer shell scripts ONLY run the fast `lint-check` job (~30s). Only boot scripts, devcontainer.json, and workflow changes trigger the slow `full-build` (~15min).

## What the Lint Check Validates

| Check | Description | Files |
|-------|-------------|-------|
| **Markdown lint** | Style/formatting rules via markdownlint-cli | Wiki articles, SKILL.md files, .hermes.md, README.md |
| **SKILL.md structure** | YAML frontmatter with `name:` field | All skills in `.devcontainer/skills/*/SKILL.md` |
| **Wiki INDEX.md** | Every article referenced in INDEX.md table | `.devcontainer/wiki/*.md` |
| **Mnemon seed.json** | Schema validation (schema_version=1, insights array) | `.devcontainer/mnemon/seed.json` |
| **Root shell syntax** | `bash -n` validation | `.devcontainer/*.sh` |
| **Skill shell syntax** | `bash -n` validation | `.devcontainer/skills/*/scripts/*.sh` |
| **Symlink persistence** | Boot scripts create correct symlinks | post-create-cmd.sh, start-hermes.sh |

## Usage

### Install Dependencies (one-time)
```bash
npm install -g markdownlint-cli
```

### Run Full Validation
```bash
bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh
```

### Run Specific Checks
```bash
bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh --markdown-only
bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh --skills-only
bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh --wiki-only
bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh --mnemon-only
bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh --shell-only
bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh --symlink-only
```

### Pre-Commit Workflow
```bash
# 1. Make your changes
# 2. Run lint check
bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh

# 3. Fix any issues reported
# 4. Commit and push
git add -A
git commit -m "your message"
git push
```

## Mandatory Rule

> **ALWAYS run the lint check before committing or creating a PR** when modifying:
> - `.devcontainer/skills/**`
> - `.devcontainer/wiki/**`
> - `.devcontainer/mnemon/**`
> - `.devcontainer/memories/**`
> - `.devcontainer/*.sh`

This is not optional — CI will fail and you'll waste time debugging in GitHub Actions.

## Integration with Git Hooks

Add to `.git/hooks/pre-commit`:
```bash
#!/bin/bash
bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh || exit 1
```

## Common Failures & Fixes

| Failure | Fix |
|---------|-----|
| Markdown lint error (MD056, MD013, etc.) | Fix line/column reported; check table column counts |
| SKILL.md missing frontmatter | Ensure file starts with `---` and has `name:` field |
| Wiki article missing from INDEX.md | Add row to INDEX.md table |
| Mnemon seed.json invalid | Run `python3 .devcontainer/mnemon/validate-seed.py .devcontainer/mnemon/seed.json` for details |
| Shell syntax error | Run `bash -n <script>` to see exact error |
| Symlink contract fails | Check boot scripts have `ln -s` for memories/skills |

## Files

| File | Purpose |
|------|---------|
| `.devcontainer/skills/ci-lint-check/SKILL.md` | Procedural skill documentation |
| `.devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh` | Validation script |
| `.github/workflows/devcontainer-ci.yml` | Source of truth for CI jobs |
| `.devcontainer/wiki/github-actions-testing-plan.md` | CI design document |

## Related Skills

- `codespace-persistent-symlinks` — Symlink architecture validated by this check
- `memory-automation` — Mnemon workflow that feeds into seed.json

## Verification

```bash
# Should output "=== ALL CHECKS PASSED ==="
bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh
```