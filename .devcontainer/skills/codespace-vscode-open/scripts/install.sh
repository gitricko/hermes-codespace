#!/usr/bin/env bash
# install.sh — Install codespace-vscode-open skill
# Copies vscode-open.sh to ~/.hermes/scripts/ for global access

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_SRC="$SKILL_DIR/scripts/vscode-open.sh"
SCRIPT_DST="$HOME/.hermes/scripts/vscode-open.sh"

mkdir -p "$HOME/.hermes/scripts"
cp "$SCRIPT_SRC" "$SCRIPT_DST"
chmod +x "$SCRIPT_DST"

echo "Installed vscode-open.sh to $SCRIPT_DST"
echo "Usage: ~/.hermes/scripts/vscode-open.sh /path/to/file.md"