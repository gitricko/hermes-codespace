---
name: codespace-vscode-open
description: Auto-discover VS Code CLI in Codespaces and open files in connected editor
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [codespace, vscode, editor, cli]
    related_skills: [codespace-gh-auth, codespace-port-visibility]
---

# codespace-vscode-open

Auto-discovers the VS Code remote CLI path in GitHub Codespaces (`/vscode/bin/linux-x64/<commit>/bin/remote-cli/code`) and provides a simple command to open files in the user's connected VS Code instance.

## Problem

The bare `code` command often fails in Codespaces because it's not on PATH or the shim is broken. The real CLI lives at a commit-specific path under `/vscode/bin/linux-x64/`.

## Solution

A script that finds the CLI automatically and opens files. Works in any Codespace with VS Code connected.

## Usage

```bash
# As a command
~/.hermes/scripts/vscode-open.sh /path/to/file.md

# Or from skill dir
.devcontainer/skills/codespace-vscode-open/scripts/vscode-open.sh /path/to/file.md
```

## How It Works

1. Searches `/vscode/bin/linux-x64/` for the `code` binary
2. Executes it with the provided file path
3. Opens the file in the user's connected VS Code window

## Installation

The script is installed to `~/.hermes/scripts/vscode-open.sh` by the skill author. No additional dependencies.

## Files

- `scripts/vscode-open.sh` — Main executable script
- `references/vscode-cli-discovery.md` — Discovery pattern and troubleshooting

## Related Skills

- `codespace-persistent-symlinks` — Same symlink pattern for persisting scripts to `~/.hermes/scripts/`
- `codespace-gh-auth` — GitHub auth in Codespaces (token extraction from VS Code server)
- `codespace-port-visibility` — Port forwarding in Codespaces

## Mnemon Persistence

This skill follows the repo's persistent knowledge pattern:
1. Skill in `.devcontainer/skills/codespace-vscode-open/` (git-tracked)
2. Script symlinked to `~/.hermes/scripts/vscode-open.sh` (runtime)
3. Wiki article in `.devcontainer/wiki/vscode-cli-codespaces.md`
4. Mnemon entry in `.devcontainer/mnemon/seed.json` (validated via `mnemon import --dry-run`)

The `start-hermes.sh` repair guard (from `codespace-persistent-symlinks`) ensures the symlink survives rebuilds.