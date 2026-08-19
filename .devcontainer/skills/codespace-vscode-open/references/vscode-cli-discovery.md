# VS Code CLI Discovery in Codespaces

## The Discovery Pattern

The VS Code remote CLI in Codespaces is at:
```
/vscode/bin/linux-x64/<commit-sha>/bin/remote-cli/code
```

Where `<commit-sha>` changes on every VS Code update.

## Reliable Discovery Script

```bash
VSCODE_CLI=$(find /vscode/bin/linux-x64 -name "code" -type f 2>/dev/null | head -1)
```

This works because:
- `/vscode/bin/linux-x64/` always exists in Codespaces with VS Code connected
- Only one `code` binary exists under it
- The path is commit-specific but the parent dir is stable

## Common Failures

| Failure | Cause | Fix |
|---------|-------|-----|
| `code: command not found` | Bare `code` not on PATH | Use discovery script |
| `code: No such file or directory` | VS Code not connected | Connect VS Code to Codespace |
| `Permission denied` | Running as wrong user | Run as codespace user (not root) |
| `find: no such file` | `/vscode` doesn't exist | Not a Codespace or VS Code not installed |

## Testing

```bash
# Verify discovery works
VSCODE_CLI=$(find /vscode/bin/linux-x64 -name "code" -type f 2>/dev/null | head -1)
echo "Found: $VSCODE_CLI"
"$VSCODE_CLI" --version

# Open a file
"$VSCODE_CLI" /path/to/file.md
```

## Integration with Hermes

The `codespace-vscode-open` skill installs this as `~/.hermes/scripts/vscode-open.sh` so any agent can use it:

```bash
~/.hermes/scripts/vscode-open.sh /workspace/PR-description.md
```

## Related

- `codespace-playbook.md` — Comprehensive Codespace operations
- `codespace-gh-auth` — GITHUB_TOKEN extraction from VS Code server process
- `codespace-port-visibility` — Port forwarding via `gh codespace ports visibility`