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

## Solution: Auto-Discovery Script

The `codespace-vscode-open` skill provides a script that finds the CLI automatically:

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
VSCODE_CLI=$(find /vscode/bin/linux-x64 -name "code" -type f 2>/dev/null | head -1)
exec "$VSCODE_CLI" "$@"
```

## Integration

- **Hermes Agent**: Use this skill to open markdown files, PR diffs, wiki articles in the user's VS Code
- **Cron jobs**: Deliver reports by opening them in the editor
- **Skills**: Any skill that needs to show a file to the user

## Related

- [codespace-playbook.md](codespace-playbook.md) — Comprehensive Codespace operations guide
- [codespace-gh-auth](codespace-gh-auth) — GitHub auth in Codespaces
- [codespace-port-visibility](codespace-port-visibility) — Port forwarding in Codespaces