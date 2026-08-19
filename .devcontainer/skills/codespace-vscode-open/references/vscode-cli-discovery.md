# VS Code CLI Discovery in Codespaces

## The Discovery Pattern

The VS Code remote CLI in Codespaces is at:
```
/vscode/bin/linux-x64/<commit-sha>/bin/remote-cli/code
```

Where `<commit-sha>` changes on every VS Code update.

## Reliable Discovery Script

The script now uses a two-step approach to find the active VS Code server's CLI:

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
```

This ensures we always use the CLI from the **active VS Code server**, not a stale version.

## Installation

```bash
# Run the install script
~/.hermes/skills/codespace/codespace-vscode-open/scripts/install.sh
# or
.devcontainer/skills/codespace-vscode-open/scripts/install.sh
```

This copies `vscode-open.sh` to `~/.hermes/scripts/vscode-open.sh` for global access.

## Integration with Hermes

After installation, any agent can use it:

```bash
~/.hermes/scripts/vscode-open.sh /workspace/PR-description.md
```

- `codespace-playbook.md` — Comprehensive Codespace operations
- `codespace-gh-auth` — GITHUB_TOKEN extraction from VS Code server process
- `codespace-port-visibility` — Port forwarding via `gh codespace ports visibility`