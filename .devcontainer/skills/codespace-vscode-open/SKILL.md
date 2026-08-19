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

## Installation

```bash
# Run the install script to copy vscode-open.sh to ~/.hermes/scripts/
~/.hermes/skills/codespace/codespace-vscode-open/scripts/install.sh

# Or from the skill directory
.devcontainer/skills/codespace-vscode-open/scripts/install.sh
```

The script is installed to `~/.hermes/scripts/vscode-open.sh` by the install script.

## Usage

```bash
# As a command
~/.hermes/scripts/vscode-open.sh /path/to/file.md

# Or from skill dir
.devcontainer/skills/codespace-vscode-open/scripts/vscode-open.sh /path/to/file.md
```

## How It Works

1. Finds the **active VS Code server PID** (`pgrep -f "server-main.js"`)
2. **Extracts commit SHA** from the server's command line to get the exact matching CLI
3. **Fallback**: if commit SHA extraction fails, picks the newest `code` binary by mtime
4. Executes the CLI with the provided file path — opens in the user's connected VS Code

This ensures we always use the CLI from the **active VS Code server**, not a stale version from a previous update.

## Files

- `scripts/vscode-open.sh` — Main executable script
- `scripts/install.sh` — Installs vscode-open.sh to `~/.hermes/scripts/`
- `references/vscode-cli-discovery.md` — Discovery pattern and troubleshooting

## Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| **Stale CLI selected** | File opens against old VS Code server, doesn't reach connected editor | Use active server's commit SHA (from `/proc/PID/cmdline`) or fallback to newest by mtime |
| **Script not installed** | `~/.hermes/scripts/vscode-open.sh: No such file or directory` | Run `scripts/install.sh` — it's not auto-linked like skills |
| **VS Code not connected** | `VS Code server not running` error | Connect VS Code desktop to Codespace before running |
| **Multiple VS Code versions** | Arbitrary `find \| head -1` picks wrong version | Sort by mtime (`-printf "%T@ %p\n" \| sort -n \| tail -1`) |

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