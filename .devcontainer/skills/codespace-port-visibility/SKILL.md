---
name: codespace-port-visibility
description: Automate Codespace port visibility via CLI w/ vscode token.
version: "1.0.0"
category: codespace
tags: [codespace, github, ports, visibility, automation, cli]
---

# Codespace Port Visibility Automation

## Problem

GitHub Codespaces require manual UI interaction to change port visibility (public/private/org). This breaks automation for services that need specific port visibility configurations.

## Solution

Extract `GITHUB_TOKEN` from the vscode-server process environment (not shell env), then use `gh codespace ports visibility` CLI.

## Usage

```bash
# Make port public
python3 scripts/set_port_visibility.py 8899 public

# Make port private
python3 scripts/set_port_visibility.py 4387 private

# List all ports
python3 scripts/set_port_visibility.py list

# Or use the CLI directly after sourcing token
source scripts/export_codespace_token.sh
gh codespace ports visibility 8080:public -c $CODESPACE_NAME
```

## NEW Port Exposure (zero manual clicks)

To expose a port that VS Code has **NOT** auto-forwarded yet (e.g. a fresh nginx slot), two steps are required:

```bash
# Step 1: Establish the tunnel (forward to a DIFFERENT local port to avoid bind conflict
# with the service already listening on <port>). gh tries to bind the local side, so if
# nginx already holds 8081, forward 8081:18081 instead.
gh codespace ports forward 8081:18081 -c $CODESPACE_NAME

# Step 2: Flip visibility to public
gh codespace ports visibility 8081:public -c $CODESPACE_NAME
```

**Why:** `gh codespace ports visibility` alone returns `404` for a port GitHub's backend
doesn't yet know about. The `forward` command registers the tunnel; `visibility` then works.
Already-forwarded ports (like 8080, auto-detected by VS Code) only need the `visibility` step.

**Script wrapper:** `scripts/expose_port.py <port> [local-port] [codespace]` does both steps.

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/set_port_visibility.py` | Main CLI: `python3 set_port_visibility.py <port> <visibility> [codespace]` |
| `scripts/expose_port.py` | NEW: forward + make public in one call (for un-forwarded ports) |
| `scripts/export_codespace_token.sh` | Exports GITHUB_TOKEN for direct `gh` usage |
| `scripts/get_codespace_token.py` | Reusable token extraction module |

## Token Extraction Logic

```python
def get_codespace_token():
    # Find code-server process (PID 399 typically)
    for pid in /proc/*/cmdline:
        if b'code-server' in open(pid, 'rb').read():
            with open(f'/proc/{pid}/environ', 'rb') as f:
                for entry in f.read().split(b'\x00'):
                    if entry.startswith(b'GITHUB_TOKEN='):
                        return entry.decode().split('=', 1)[1]
```

## Integration Example

```bash
# 1. Make service port private for security
python3 scripts/set_port_visibility.py 4387 private

# 2. Make proxy port public for access
python3 scripts/set_port_visibility.py 8080 public

# 3. Start services
LAVISH_AXI_NO_OPEN=1 node dist/cli.mjs sample.html --no-open &
sudo nginx -g 'daemon off;' &
```

## Prerequisites

- `gh` CLI installed (`pnpm add -g @github/cli` or `apt install gh`)
- Running in a GitHub Codespace (vscode-server process exists)
- `CODESPACE_NAME` environment variable set (auto-set in Codespaces)

## Related Skills

- `codespace-gh-auth` — GitHub auth setup for Codespaces
- `github-codespace` — Full Codespace workflow (auth, CI, PR)