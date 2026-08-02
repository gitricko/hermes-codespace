# Hermes-CodeSpace: Repository Deep Dive

> **Purpose**: Comprehensive analysis of the hermes-codespace repository — what it does, how it's built, what's used vs unused, and how it's verified. Intended as persistent documentation for future Codespace sessions.
>
> **Last updated**: 2026-08-01

---

## 1. What This Repository Is

`hermes-codespace` is a **GitHub Codespaces template** that provides a zero-config AI coding environment. When someone forks this repo (or uses it as a template) and opens it in a Codespace, the following stack is automatically installed and configured in ~5-10 minutes:

| Component | Purpose | Port |
|-----------|---------|------|
| **Hermes Agent** | AI coding agent with memory, skills, multi-step tasks | 9119 (gateway+dashboard) |
| **OmniRoute** | Primary LLM router — 8 free models, auto-routing | 20128 |
| **ModelRelay** | Fallback LLM router | 7352 |
| **Ollama** | Local embeddings (nomic-embed-text) for Mnemon | 11434 |
| **Mnemon** | Persistent graph memory (no token limits, cross-session) | — |
| **Claude Code** | Anthropic CLI agent (preconfigured to use OmniRoute) | — |
| **Cline** | VS Code coding agent (preconfigured to use OmniRoute) | — |

The core idea: **free LLM models forever** via OmniRoute/ModelRelay, with **persistent memory** via Mnemon, all inside GitHub Codespaces (free tier: 60 hrs/month).

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      GitHub Codespace                           │
├─────────────────────────────────────────────────────────────────┤
│  VS Code + Extensions                                           │
│  ├─ Hermes Extension (ACP protocol)                             │
│  ├─ Claude Code Extension                                       │
│  └─ Cline Extension                                             │
├─────────────────────────────────────────────────────────────────┤
│  Terminal Agents                                                │
│  ├─ hermes (CLI + Gateway :9119 + Dashboard :9119)              │
│  └─ claude (CLI via ModelRelay/OmniRoute)                       │
├─────────────────────────────────────────────────────────────────┤
│  Model Routers (OpenAI-compatible)                              │
│  ├─ OmniRoute  :20128  → 8 free models (auto-fastest combo)    │
│  ├─ ModelRelay :7352   → fallback router                        │
│  └─ Ollama     :11434  → local embeddings (nomic-embed-text)   │
├─────────────────────────────────────────────────────────────────┤
│  Memory Layer                                                   │
│  └─ Mnemon (SQLite graph DB, no token limits)                   │
│      ├─ Hermes plugin (gitricko/hermes-plugin-mnemon)           │
│      └─ Claude Code integration (mnemon setup --target)         │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Startup Flow

### Phase 1: `postCreateCommand` (runs ONCE on first container creation)

Script: `.devcontainer/post-create-cmd.sh` (319 lines)

| Step | What | Details |
|------|------|---------|
| 1 | System deps | `apt-get install zsh ripgrep` |
| 2 | Ollama | Install binary, start `ollama serve`, pull `nomic-embed-text` (async) |
| 3 | Hermes Agent | Install from NousResearch/hermes-agent (v2026.7.20), ACP protocol |
| 4 | Hermes config | First-run only: set model=auto-fastest, provider=omniroute, fallback=modelrelay, memory=mnemon, approvals=off, max_turns=120 |
| 5 | Skills | Copy `skill-memory-automation.md` → `~/.hermes/skills/memory-automation/SKILL.md` |
| 6 | User memory | Copy `.hermes.md` → `~/.hermes.md` (Mnemon instructions) |
| 7 | ModelRelay | Install from github:gitricko/modelrelay, start on :7352 |
| 8 | OmniRoute | Install (v3.8.49), **repair hollow dist deps**, start on :20128 |
| 9 | Tailscale | Install VPN (not used post-install) |
| 10 | Mnemon | Download binary from GitHub releases (v0.1.17) |
| 11 | Cline | Install npm package, copy config files |
| 12 | Claude Code | Install CLI, copy CLAUDE.md + settings, configure VS Code for Omniroute |
| 13 | Mnemon+Claude | `mnemon setup --yes --global --target claude-code` |
| 14 | OmniRoute config | Wait for ready, disable login (SQLite), create `auto-fastest` combo with 8 free models, enable MCP, register with Hermes |

### Phase 2: `postStartCommand` (runs on EVERY codespace start)

Two scripts run in sequence:

#### a) `.devcontainer/codespace-cleanup.sh` (308 lines)
Disk reclamation — safe to re-run (idempotent). Removes:
- Ollama GPU libraries (CUDA/Vulkan — CPU fallback works)
- Package manager caches (pip, npm, uv, electron, node-gyp)
- Unused language runtimes (PHP, Ruby, SDKMAN/Java)
- **Stale VS Code server copies** (biggest win, ~17G on /vscode)
- Stale VS Code serverCache entries
- Unused npm packages (cline)
- Old NVM node versions
- Unused tools (Hugo, Go, Minikube, Helm, kubectl, Copilot CLI)

**Safety**: Does NOT touch Ollama models, active VS Code, Hermes, OmniRoute, or active Node/Python runtimes.

#### b) `.devcontainer/start-hermes.sh` (122 lines)
Service startup orchestrator:
1. Start ModelRelay (if not running)
2. Start OmniRoute (if not running)
3. Start Ollama + pull nomic-embed-text (if not running)
4. Install Telegram bot dependency (python-telegram-bot)
5. **Update Mnemon plugin** — clones gitricko/hermes-plugin-mnemon, compares with installed version, copies if different
6. Start Hermes Gateway (`hermes gateway run --no-supervise`)
7. Start Hermes Dashboard (`hermes dashboard --port 9119 --no-open`)
8. Set up USER.md reminder (Mnemon as primary memory)
9. Wait for dashboard health (poll localhost:9119, up to 60s)
10. Run `self-check.sh` (health diagnostics)

---

## 4. The Mnemon Memory System

### What It Is
Mnemon is a persistent graph-memory database for AI agents. It stores insights as nodes with relationships, supporting semantic search via Ollama embeddings. Key properties:
- **No token limits** (unlike Hermes built-in `memory()` which is capped at ~2.2K chars)
- **Cross-session persistence** — memories survive Codespace restarts
- **Cross-agent sharing** — both Hermes and Claude Code can read/write the same memory

### How It's Installed
1. Binary: downloaded from `mnemon-dev/mnemon` GitHub releases to `/usr/local/bin/mnemon`
2. Database: `~/.mnemon/` directory (created on first use)
3. Hermes plugin: cloned from `gitricko/hermes-plugin-mnemon` on every start, synced to `~/.hermes/plugins/mnemon/`
4. Claude Code: integrated via `mnemon setup --yes --global --target claude-code`

### How Hermes Uses It
- Config: `memory.provider: mnemon` in `~/.hermes/config.yaml`
- Tools exposed: `mnemon_remember()`, `mnemon_recall()`, `mnemon_forget()`
- **USER.md** (`~/.hermes/memories/USER.md`) instructs Hermes to use Mnemon as primary memory
- **memory-automation skill** (`~/.hermes/skills/memory-automation/SKILL.md`) defines the workflow

### Memory Automation Workflow
Defined in `.devcontainer/skill-memory-automation.md` (247 lines):

**Recall (before responding)**:
- Session start: `mnemon_recall("", intent="GENERAL", limit=20)` — broad context load
- Before each turn: hook runs `mnemon_recall("<topic>", limit=10)` — topic-specific
- Manual fallback: if hook returns nothing, run recall manually

**Save (after every response)** — Two-tier system:
- **Direct call** (1-2 items): `mnemon_remember(text, category, importance, entities, tags)` — zero overhead
- **Delegated subagent** (3+ items or complex extraction): `delegate_task()` with CLI commands — worth the ~20K token spawn cost

**Categories**: fact, preference, decision, insight, context, general
**Importance**: 1 (trivial) to 5 (critical — user identity, security)

### What NOT to Save
- Code already in git
- Public API docs
- Transient state (greetings, current time)
- Things already in config files

---

## 5. Verification & Validation

### Self-Check Script (`self-check.sh`, 485 lines)

A comprehensive health diagnostic that probes 8 areas:

| # | Check | What It Probes | Failure Mode |
|---|-------|----------------|--------------|
| 1 | **Services** | HTTP response on ports 7352, 20128, 9119 | Critical if any port down |
| 2 | **Models** | OmniRoute /v1/models endpoint | Warn if 0 models |
| 3 | **Mnemon** | Binary exists, database directory found | Critical if binary missing |
| 4 | **Hermes** | Config file valid, gateway responds | Critical if config/gateway missing |
| 5 | **Disk** | `df` usage (warn at 85%, critical at 95%) | Warn/critical |
| 6 | **Memory** | `free -m` usage (warn at 90%) | Warn |
| 7 | **Cron** | `hermes cron list` registered jobs | OK if none (fresh boot) |
| 8 | **Ollama** | Binary, API, model listed, embedding test | Critical if binary missing |

**Features**:
- Polls services with 60s timeout (retries every 5s)
- Outputs human-readable report to stdout
- Outputs machine-parseable JSON to `/tmp/health-report.json`
- **Auto-discovers Telegram** delivery from Hermes config — sends health alerts if configured
- Exit codes: 0=pass, 1=warnings, 2=critical failures
- Configurable via env vars: `HERMES_WEBTOP_SKIP_CHECKS`, `HERMES_WEBTOP_DISK_WARN_PCT`, `HERMES_WEBTOP_CRITICAL_SERVICES`

### GitHub Actions CI Pipeline

File: `.github/workflows/devcontainer-ci.yml`

```yaml
name: Dev Container CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
jobs:
  test-devcontainer:
    name: Build & Smoke Test
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - Checkout repository
      - Run post-create-cmd.sh (full install)
      - Run start-hermes.sh (service startup)
      - Run self-check.sh (health verification)
```

**What this validates**: Every push/PR runs the ENTIRE install + startup + health check. This catches:
- Broken installs (npm packages, curl installs, apt packages)
- Service startup failures
- Configuration errors
- Missing dependencies
- OmniRoute/ModelRelay/Ollama integration issues

**Additional CI checks** (auto-configured by GitHub):
- **CodeQL**: Security analysis
- **copilot-pull-request-reviewer**: Automated code review
- **Analyze (actions)**: Workflow analysis

### How to Run Health Check Manually

```bash
# Full health check
bash .devcontainer/self-check.sh

# Skip specific checks
HERMES_WEBTOP_SKIP_CHECKS=memory,cron bash .devcontainer/self-check.sh

# Adjust disk warning threshold
HERMES_WEBTOP_DISK_WARN_PCT=80 bash .devcontainer/self-check.sh

# Check the JSON report
cat /tmp/health-report.json | python3 -m json.tool
```

---

## 6. What's Used vs What's Not

### Actively Used (Core Stack)

| Component | Where Referenced | Status |
|-----------|------------------|--------|
| Hermes Agent | post-create, start-hermes, CI, config | Active — primary agent |
| OmniRoute | post-create, start-hermes, CI, config | Active — primary LLM router |
| ModelRelay | post-create, start-hermes, CI, config | Active — fallback router |
| Ollama | post-create, start-hermes, self-check | Active — embeddings for Mnemon |
| Mnemon | post-create, start-hermes, self-check, skill | Active — persistent memory |
| Claude Code | post-create, devcontainer.json | Active — secondary agent |
| Cline | post-create, devcontainer.json | Active — VS Code agent |
| self-check.sh | start-hermes, CI | Active — health verification |
| codespace-cleanup.sh | postStartCommand | Active — disk management |
| free-disk.sh | Referenced in README | **Semi-used** — manual only |

### Installed But Not Actively Used

| Component | Why It's There | Status |
|-----------|---------------|--------|
| **Tailscale** | Installed in post-create (line 215) but never configured or started | **Unused** — dead code |
| **Dependabot** | `.github/dependabot.yml` has empty `package-ecosystem: ""` | **Broken** — never triggers updates |
| **Telegram bot dependency** | `python-telegram-bot` installed in start-hermes but only used if env vars set | **Conditional** — works but not configured by default |

### Redundant / Overlapping Config

| File | Issue |
|------|-------|
| `.hermes.md` (template) | Says "delegate subagent" for all saves — the skill says direct calls are fine for 1-2 items |
| `CLAUDE.md` | Same memory instructions as skill-memory-automation.md — duplicates |
| `cline-globalState.json` | Gets overwritten by `post-create-cmd.sh` smart_copy — pre-configure is pointless |
| `cline-secrets.json` | Same as above |

### Documentation Files

| File | Purpose | Actively Used? |
|------|---------|----------------|
| `README.md` | User-facing docs | Yes — primary documentation |
| `CODESPACE_PLAYBOOK.md` | Agent auth guide | Yes — for agent sessions |
| `GITHUB_ACTIONS_TESTING_PLAN.md` | CI testing plan | Historical — plan was implemented |
| `omniroute-upstream-bug.md` | Bug report for OmniRoute | Reference — ready to file |
| `skill-memory-automation.md` | Memory skill | Yes — copied to skills dir |

---

## 7. Key Technical Details

### OmniRoute Hollow Dependency Workaround

**Problem**: OmniRoute npm tarball ships incomplete `dist/node_modules/` — many packages have only `package.json` stubs with no JS/native code. The MCP server crashes on startup with `Cannot find package 'undici/index.js'`.

**Solution** (in post-create-cmd.sh, lines 145-196):
```bash
repair_omniroute_dist_deps() {
  # Finds hollow packages (no .js/.mjs/.cjs/.node/.so files)
  # Copies full packages from sibling node_modules/ to dist/node_modules/
}
```

**Status**: Upstream bug (documented in `omniroute-upstream-bug.md`, ready to file). Workaround auto-detects and repairs across version bumps.

### OmniRoute Login Bypass

OmniRoute is configured to not require login by directly modifying its SQLite database:
```python
import sqlite3
conn = sqlite3.connect('$HOME/.omniroute/storage.sqlite')
conn.execute('UPDATE key_value SET value = ? WHERE key = ?', ('false', 'requireLogin'))
conn.commit()
```

### Mnemon Plugin Sync (Every Start)

`start-hermes.sh` clones `gitricko/hermes-plugin-mnemon` on every start, diffs with installed version, and updates if different. This ensures the plugin stays current without requiring Codespace rebuild.

### Auto-Fastest Model Combo

8 free models configured in OmniRoute with `auto` strategy:
- `oc/deepseek-v4-flash-free` (OpenCode)
- `oc/big-pickle` (OpenCode)
- `opencode-zen/deepseek-v4-flash-free` (OpenCode-Zen)
- `opencode-zen/hy3-free` (OpenCode-Zen)
- `opencode-zen/mimo-v2.5-free` (OpenCode-Zen)
- `opencode-zen/north-mini-code-free` (OpenCode-Zen)
- `opencode-zen/nemotron-3-ultra-free` (OpenCode-Zen)
- `opencode-zen/big-pickle` (OpenCode-Zen)

Strategy: `auto` — benchmarks all models periodically, routes to fastest healthy one. Config: maxRetries=2, retryDelayMs=1000, timeoutMs=120000, healthCheckEnabled=true.

---

## 8. How to Contribute / Validate Changes

### Before Pushing

```bash
# Run the full smoke test locally
bash .devcontainer/post-create-cmd.sh   # Only needed once
bash .devcontainer/start-hermes.sh      # Starts all services
bash .devcontainer/self-check.sh        # Health check

# Quick health check (if services already running)
bash .devcontainer/self-check.sh
cat /tmp/health-report.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'Exit: {d[\"exit_code\"]}, Critical: {d[\"critical\"]}, Warnings: {d[\"warnings\"]}')"
```

### CI Will Catch

- Broken installs (any package, curl, apt)
- Service startup failures
- Configuration errors
- Missing dependencies
- OmniRoute/ModelRelay/Ollama integration breakage
- Health check failures (ports, models, disk, memory)

### Updating Versions

Edit the version variables at the top of `post-create-cmd.sh`:
```bash
HERMES_VERSION="v2026.7.20"      # Update here
OMNIROUTE_VERSION=3.8.49         # Update here
MODELRELAY_VERSION=1.18.0
OLLAMA_VERSION=0.32.5
NODE_VERSION=24.18.0
MNEMON_VERSION=0.1.17
```

Also update the corresponding badges in `README.md`.

### Upstream Sync (After Forking)

```bash
cd .devcontainer && make update-deps
git diff .devcontainer/
git add -A && git commit -m "Update .devcontainer from upstream"
```

---

## 9. Service Logs

| Service | Log Location |
|---------|-------------|
| Full setup | `/tmp/hermes-codespace.log` |
| ModelRelay | `/tmp/modelrelay.log` |
| OmniRoute | `/tmp/omniroute.log` |
| Ollama | `/tmp/ollama.log` |
| Hermes Gateway | `~/.hermes/logs/gateway.log` |
| Hermes Dashboard | `~/.hermes/logs/dashboard.log` |
| Ollama model pull | `/tmp/ollama-pull.log` |
| Health report | `/tmp/health-report.json` |

---

*This document is a living analysis. Update it when the repository structure or behavior changes.*
