# VS Code CLI in GitHub Codespaces

## Overview

In GitHub Codespaces, the VS Code remote CLI (`code`) is not on the default PATH. It lives at a commit-specific path:

```
/vscode/bin/linux-x64/<commit-sha>/bin/remote-cli/code
```

Where `<commit-sha>` is the VS Code server commit hash (e.g., `a5b500951314efd502d07465bd138dfbd714a960`).

## Why This Matters

- The bare `code` command often fails in headless/terminal-only Codespaces
- The real CLI works perfectly when VS Code desktop is connected to the Codespace
- Path changes on every VS Code update (new commit SHA)
- Multiple VS Code versions may coexist after updates — must select the **active server's** CLI

## Solution: Auto-Discovery Script

The `codespace-vscode-open` skill provides a script that finds the **active server's** CLI automatically:

```bash
# Location
~/.hermes/scripts/vscode-open.sh
# or
.devcontainer/skills/codespace-vscode-open/scripts/vscode-open.sh
```

```bash
# Usage
vscode-open.sh /path/to/file.md
```

## How It Works

```bash
# 1. Find the active VS Code server PID
VSCODE_PID=$(pgrep -f "server-main.js" | head -1)

# 2. Extract commit SHA from server's command line, or fallback to newest by mtime
VSCODE_CMDLINE=$(cat /proc/$VSCODE_PID/cmdline 2>/dev/null | tr '\0' ' ')
COMMIT_SHA=$(echo "$VSCODE_CMDLINE" | grep -oE '/vscode/bin/linux-x64/[a-f0-9]{40}/' | head -1 | cut -d'/' -f5)

if [[ -n "$COMMIT_SHA" && -x "/vscode/bin/linux-x64/$COMMIT_SHA/bin/remote-cli/code" ]]; then
    VSCODE_CLI="/vscode/bin/linux-x64/$COMMIT_SHA/bin/remote-cli/code"
else
    # Fallback: find the newest code binary (by mtime)
    VSCODE_CLI=$(find /vscode/bin/linux-x64 -name "code" -type f -executable 2>/dev/null -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2-)
fi

exec "$VSCODE_CLI" "$@"
```

This ensures we always use the CLI from the **active VS Code server**, not a stale version from a previous update.

## Installation

```bash
# Run the install script
~/.hermes/skills/codespace/codespace-vscode-open/scripts/install.sh
# or
.devcontainer/skills/codespace-vscode-open/scripts/install.sh
```

This copies `vscode-open.sh` to `~/.hermes/scripts/vscode-open.sh` for global access.

## Integration

- **Hermes Agent**: Use this skill to open markdown files, PR diffs, wiki articles in the user's VS Code
- **Cron jobs**: Deliver reports by opening them in the editor
- **Skills**: Any skill that needs to show a file to the user

## Related

- [codespace-playbook.md](codespace-playbook.md) — Comprehensive Codespace operations guide
- [codespace-gh-auth](codespace-gh-auth) — GitHub auth in Codespaces
- [codespace-port-visibility](codespace-port-visibility) — Port forwarding in Codespaces