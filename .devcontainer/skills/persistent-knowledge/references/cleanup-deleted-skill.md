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

## Cleanup Procedure for Deleted Skills/Projects

When a skill or project is deleted, remove all traces from the persistent knowledge system:

### 1. Wiki Files
- Delete the skill's wiki article(s) from `.devcontainer/wiki/`
- Remove table rows from `.devcontainer/wiki/INDEX.md`
- Search and remove cross-references in other wiki articles:
  ```bash
  grep -r "<skill-name>" .devcontainer/wiki/
  ```

### 2. Skill Directory
- Delete the skill directory from `.devcontainer/skills/<skill-name>/`

### 3. Mnemon Live Database
- Find and forget relevant insights:
  ```bash
  mnemon recall "<skill-name>" --limit 50
  mnemon forget <insight-id>  # for each relevant insight
  ```

### 4. Mnemon Seed (seed.json)
- Remove insights referencing the deleted skill:
  ```python
  import json
  with open('.devcontainer/mnemon/seed.json') as f:
      data = json.load(f)
  data['insights'] = [i for i in data['insights'] 
                      if '<skill-name>' not in i.get('content', '') 
                      and '<skill-name>' not in i.get('entities', [])]
  with open('.devcontainer/mnemon/seed.json', 'w') as f:
      json.dump(data, f, indent=2)
  ```

### 5. Related Skill Files
- Check other skills for references in:
  - SKILL.md (examples, related skills, triggers)
  - templates/ and scripts/ (docstrings, comments)
  - references/ (cross-links)
  ```bash
  grep -r "<skill-name>" .devcontainer/skills/
  ```

### 6. Verification
- Confirm no references remain:
  ```bash
  grep -r "<skill-name>" .devcontainer/ --include="*.md" --include="*.json" --include="*.py" --include="*.sh" --include="*.yml"
  ```

### Example: lavish-axi + cdp-browser-testing Cleanup
This session removed:
- 3 wiki articles (lavish-axi-codespace-setup.md, lavish-axi-skill-design.md, cdp-browser-testing.md)
- 1 skill directory (cdp-browser-testing/)
- 7 seed.json insights (lavish-axi)
- 3 mnemon live DB insights (lavish-axi)
- Cross-references in 5 other wiki files
- Cross-references in 4 skill files