# Codespace Port Visibility Automation

## Overview

GitHub Codespaces require manual UI interaction to change port visibility (public/private/org). This breaks automation for services that need specific port visibility configurations.

This article documents the reference architecture for automating Codespace port visibility via CLI using the VS Code server's GitHub token.

## The Problem

VS Code auto-detects and forwards some ports (e.g., 8080), but:
- New ports started by services (nginx, etc.) are not auto-forwarded
- Changing visibility requires clicking in the VS Code Ports panel
- No CLI existed until `gh codespace ports` commands were added

## Solution Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Codespace Environment                     │
│                                                              │
│  ┌──────────────────┐    Extract GITHUB_TOKEN    ┌────────┐ │
│  │  VS Code Server  │ ─────────────────────────► │ Script │ │
│  │  (server-main.js)│   /proc/PID/environ        │        │ │
│  └──────────────────┘                            └────┬───┘ │
│                                                      │     │
│                    gh codespace ports                ▼     │
│  ┌──────────────────┐    forward + visibility    ┌────────┐ │
│  │  GitHub Backend  │ ◄───────────────────────── │ gh CLI │ │
│  │  (port registry) │                            └────────┘ │
│  └──────────────────┘                                       │
└─────────────────────────────────────────────────────────────┘
```

## Token Extraction (Reusable Module)

```python
def get_codespace_token():
    # Find code-server process
    for pid in /proc/*/cmdline:
        if b'code-server' in open(pid, 'rb').read():
            with open(f'/proc/{pid}/environ', 'rb') as f:
                for entry in f.read().split(b'\x00'):
                    if entry.startswith(b'GITHUB_TOKEN='):
                        return entry.decode().split('=', 1)[1]
```

## Port Exposure: Two-Step Process (Critical)

To expose a port that VS Code has **NOT** auto-forwarded yet (e.g., a fresh nginx slot), **two steps are required**:

### Step 1: Establish the Tunnel

```bash
# Forward to a DIFFERENT local port to avoid bind conflict
# with the service already listening on <port>
# gh tries to bind the local side, so if nginx holds 8081, use 8081:18081
gh codespace ports forward 8081:18081 -c $CODESPACE_NAME
```

### Step 2: Flip Visibility to Public

```bash
gh codespace ports visibility 8081:public -c $CODESPACE_NAME
```

**Why both steps**: `gh codespace ports visibility` alone returns `404` for a port GitHub's backend doesn't yet know about. The `forward` command registers the tunnel; `visibility` then works.

Already-forwarded ports (like 8080, auto-detected by VS Code) only need the `visibility` step.

## Script Wrappers

### `set_port_visibility.py` — Main CLI

```bash
# Make port public
python3 scripts/set_port_visibility.py 8899 public

# Make port private
python3 scripts/set_port_visibility.py 4387 private

# List all ports
python3 scripts/set_port_visibility.py list
```

### `expose_port.py` — Forward + Public in One Call

```bash
# For un-forwarded ports: does both steps
python3 scripts/expose_port.py <port> [local-port] [codespace]
```

### `export_codespace_token.sh` — For Direct gh Usage

```bash
source scripts/export_codespace_token.sh
gh codespace ports visibility 8080:public -c $CODESPACE_NAME
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

## Port Scheme Reference (Slot-based)

## Prerequisites

- `gh` CLI installed (`pnpm add -g @github/cli` or `apt install gh`)
- Running in a GitHub Codespace (vscode-server process exists)
- `CODESPACE_NAME` environment variable set (auto-set in Codespaces)

## Related

- **Skill**: `.devcontainer/skills/codespace-port-visibility/` — Procedural how-to
- **Skill**: `.devcontainer/skills/codespace-gh-auth/` — Token extraction from VS Code
- **Wiki**: [codespace-gh-auth.md](codespace-gh-auth.md) — Token extraction details
- **Wiki**: [github-codespace.md](github-codespace.md) — Complete Codespace workflow