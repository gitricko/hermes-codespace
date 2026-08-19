#!/usr/bin/env bash
# vscode-open.sh — Auto-discover VS Code CLI in Codespaces and open files
# Part of codespace-vscode-open skill

# Find the active VS Code server PID first
VSCODE_PID=$(pgrep -f "server-main.js" | head -1)

if [[ -z "$VSCODE_PID" ]]; then
    echo "ERROR: VS Code server not running. Make sure VS Code is connected to this Codespace." >&2
    exit 1
fi

# Extract the commit SHA from the server's command line
# The command line contains the commit SHA path
VSCODE_CMDLINE=$(cat /proc/$VSCODE_PID/cmdline 2>/dev/null | tr '\0' ' ')
COMMIT_SHA=$(echo "$VSCODE_CMDLINE" | grep -oE '/vscode/bin/linux-x64/[a-f0-9]{40}/' | head -1 | cut -d'/' -f5)

if [[ -n "$COMMIT_SHA" && -x "/vscode/bin/linux-x64/$COMMIT_SHA/bin/remote-cli/code" ]]; then
    VSCODE_CLI="/vscode/bin/linux-x64/$COMMIT_SHA/bin/remote-cli/code"
else
    # Fallback: find the newest code binary (by mtime) to match active server
    VSCODE_CLI=$(find /vscode/bin/linux-x64 -name "code" -type f -executable 2>/dev/null -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2-)
fi

if [[ -z "$VSCODE_CLI" || ! -x "$VSCODE_CLI" ]]; then
    echo "ERROR: VS Code CLI not found or not executable." >&2
    echo "Make sure VS Code is connected to this Codespace." >&2
    exit 1
fi

exec "$VSCODE_CLI" "$@"