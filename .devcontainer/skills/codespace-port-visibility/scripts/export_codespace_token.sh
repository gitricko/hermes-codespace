#!/bin/bash
# Source this script to export GITHUB_TOKEN for direct gh CLI usage
# Usage: source scripts/export_codespace_token.sh

set -e

# Find code-server process and extract GITHUB_TOKEN
for pid_path in /proc/*/cmdline; do
    if [[ -r "$pid_path" ]]; then
        cmdline=$(cat "$pid_path" 2>/dev/null | tr '\0' ' ')
        if [[ "$cmdline" == *"code-server"* ]]; then
            pid=$(basename "$(dirname "$pid_path")")
            if [[ -r "/proc/$pid/environ" ]]; then
                while IFS= read -r -d '' entry; do
                    if [[ "$entry" == GITHUB_TOKEN=* ]]; then
                        export GITHUB_TOKEN="${entry#GITHUB_TOKEN=}"
                        echo "export GITHUB_TOKEN=$GITHUB_TOKEN"
                        exit 0
                    fi
                done < "/proc/$pid/environ"
            fi
        fi
    fi
done

echo "Error: Could not find GITHUB_TOKEN in vscode-server process" >&2
exit 1