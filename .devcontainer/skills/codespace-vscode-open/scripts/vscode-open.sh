#!/usr/bin/env bash
# vscode-open.sh — Auto-discover VS Code CLI in Codespaces and open files
# Part of codespace-vscode-open skill

# Find the VS Code remote CLI
VSCODE_CLI=$(find /vscode/bin/linux-x64 -name "code" -type f 2>/dev/null | head -1)

if [[ -z "$VSCODE_CLI" ]]; then
    echo "ERROR: VS Code CLI not found in /vscode/bin/linux-x64/" >&2
    echo "Make sure VS Code is connected to this Codespace." >&2
    exit 1
fi

exec "$VSCODE_CLI" "$@"