# Hermes-CodeSpace

> **A GitHub Codespaces-ready dev container template pre-configured with Hermes AI coding agent, free LLM routers, and local AI infrastructure — ready to code in seconds.**

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Dev Container](https://img.shields.io/badge/devcontainer-ready-blue?logo=docker)](https://containers.dev/)
[![Hermes Agent](https://img.shields.io/badge/Hermes%20Agent-v2026.7.7.2-purple?logo=github)](https://github.com/NousResearch/hermes-agent)
[![ModelRelay](https://img.shields.io/badge/ModelRelay-1.18.0-green?logo=npm)](https://www.npmjs.com/package/modelrelay)
[![OmniRoute](https://img.shields.io/badge/OmniRoute-3.8.48-orange?logo=npm)](https://www.npmjs.com/package/omniroute)

Fork this repo before [![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/gitricko/hermes-codespace)

---

## Overview

Hermes-CodeSpace is a **zero-config GitHub Codespaces template** that spins up a fully-featured AI development environment in seconds. It ships with:

| Component | Purpose | Port |
|-----------|---------|------|
| **[Hermes Agent](https://github.com/NousResearch/hermes-agent)** | AI coding agent with memory, skills, and multi-step task execution | 9119 (Dashboard) |
| **[Hermes VS Code Extension](https://marketplace.visualstudio.com/items?itemName=JoveRina.rina-hermes-acp)** | Full IDE integration — chat, inline suggestions, terminal access | — |
| **[Claude Code](https://github.com/anthropics/claude-code)** | Anthropic's CLI agent — preconfigured with Omniroute | — |
| **[Cline](https://marketplace.visualstudio.com/items?itemName=saoudrizwan.claude-dev)** | VS Code coding agent — preconfigured with Omniroute | — |
| **[ModelRelay](https://www.npmjs.com/package/modelrelay)** | OpenAI-compatible local router — benchmarks free coding models and routes to the best provider | 7352 |
| **[OmniRoute](https://www.npmjs.com/package/omniroute)** | OpenAI-compatible local router with MCP support — benchmarks free models and routes to the best provider | 20128 |
| **[Mnemon](https://github.com/mnemon-dev/mnemon)** | Persistent memory layer for AI agents (no token limits) | — |
| **[Ollama](https://ollama.com/)** | Local LLM inference server for `nomic-embed-text` to support Mnemon | 11434 |

---

## Why Hermes-CodeSpace?

| Problem | Solution |
|---------|----------|
| GitHub Copilot free monthly trial expires | **Free forever** — runs on free tier models via OmniRoute/ModelRelay |
| Vendor lock-in | **Multi-provider routing** — auto-routes to best free model (DeepSeek, Nemotron, etc.) |
| Context loss between sessions | **Mnemon memory** — persistent, unlimited memory across sessions |
| Context switching between tools | **Unified IDE** — Hermes, Claude Code, and Cline all in VS Code |
| Local hardware limits | **Cloud-native** — runs in GitHub Codespaces (free tier: 60 hrs/mo) |

---

## Quick Start

### Option 1: Use as Template (Recommended)

1. Click **"Use this template"** → **"Create a new repository"**
2. Name your repo → **Create**
3. Open your new repo → **Code** → **Codespaces** → **Create codespace on main**
4. Wait 5–10 minutes for initial setup (first time only)
5. Start coding with Hermes/Claude/Cline !

### Option 2: Fork & Go Private

1. **Fork** this repository
2. **Make it private** (Settings → Danger Zone → "Change visibility" → Private)
3. **Leave fork network** (Settings → Danger Zone → "Leave fork network")
4. Open in Codespaces → Start coding privately

> **Tip:** To pull future updates from upstream after going private:
> ```bash
> cd .devcontainer && make update-deps
> git diff .devcontainer/    # Review changes
> git add -A && git commit -m "Update .devcontainer from upstream"
> ```

---

## What Happens on First Launch

The `postCreateCommand` runs once during container creation (~5–10 min):

| Step | Description |
|------|-------------|
| 1️⃣ | Install system deps: `zsh`, `ripgrep`, `tailscale` |
| 2️⃣ | Install **Ollama** + pull `nomic-embed-text` embedding model |
| 3️⃣ | Install **Hermes Agent** (v2026.7.7.2) with ACP protocol |
| 4️⃣ | Install **ModelRelay** (global npm) + start on port 7352 |
| 5️⃣ | Install **OmniRoute** (v3.8.48) |
| 6️⃣ | Configure **OmniRoute**: disable login, create `auto-fastest` combo with 8 free models |
| 7️⃣ | Configure **Hermes**: `auto-fastest` model, OmniRoute provider, ModelRelay fallback, memory enabled (Mnemon), approvals off |
| 8️⃣ | Install **Mnemon** memory CLI + integrate with Hermes & Claude Code |
| 9️⃣ | Install **Cline** + **Claude Code CLI** + VS Code extensions |
| 🔟 | Pre-configure VS Code settings for Claude Code (Omniroute endpoint) |

The `postStartCommand` runs on every codespace start (~30 sec):
- Starts ModelRelay, OmniRoute, Ollama
- Starts Hermes Gateway (port 9119) + Dashboard (port 9119)
- Runs health self-check

---

## Verified Ports

After startup, check the **PORTS** panel (VS Code bottom panel) for:

| Port | Service | Access |
|------|---------|--------|
| **7352** | ModelRelay API | `http://localhost:7352/v1` |
| **20128** | OmniRoute API | `http://localhost:20128/v1` |
| **9119** | Hermes Gateway + Dashboard | `http://localhost:9119` |
| **11434** | Ollama API | `http://localhost:11434` |

> **Dashboard tip:** Open port 9119 → Hermes Dashboard shows agent status, sessions, and model routing.

---

## Using the Agents

### Hermes Agent (Terminal)
```bash
hermes                    # Interactive chat
hermes "refactor foo.ts"  # One-shot task
```

### Hermes VS Code Extension
- **Cmd/Ctrl + Shift + P** → "Hermes: Chat"
- Inline suggestions via ACP protocol
- Terminal integration via `hermes` command

### Claude Code CLI
```bash
claude                    # Interactive (uses ModelRelay @ localhost:7352)
claude -p "fix bug"       # One-shot
```

### Cline (VS Code Extension)
- Click Cline icon in sidebar → Chat with free models via Omniroute

---

## Memory & Persistence (Mnemon)

Hermes-CodeSpace's Agents integrates **Mnemon** for persistent, unlimited memory that are across session and agents. **Hermes auto-uses Mnemon** when `memory.provider=mnemon` (configured by default). Claude Code also gets Mnemon via `mnemon setup --yes --global --target claude-code`.

#### Example
```bash
# Get Claude to remember something
claude -p "remember my name is fart-man"  

# Get Hermes to recall
hermes chat -q "what is my name"
```
---

## Configuration

### Hermes Config (`~/.hermes/config.yaml`)
```yaml
model:
  default: auto-fastest
  provider: omniroute
providers:
  omniroute:
    base_url: http://localhost:20128/v1
    api_key: no-key-needed
  modelrelay:
    base_url: http://localhost:7352/v1
    api_key: no-key-needed
fallback_providers:
  provider: modelrelay
  model: auto-fastest
memory:
  memory_enabled: true
  user_profile_enabled: true
  provider: mnemon
approvals:
  mode: off
agent:
  max_turns: 120
```

### OmniRoute Models (Pre-configured `auto-fastest` Combo)
| Model | Provider |
|-------|----------|
| `oc/deepseek-v4-flash-free` | OpenCode |
| `oc/big-pickle` | OpenCode |
| `opencode-zen/deepseek-v4-flash-free` | OpenCode-Zen |
| `opencode-zen/hy3-free` | OpenCode-Zen |
| `opencode-zen/mimo-v2.5-free` | OpenCode-Zen |
| `opencode-zen/north-mini-code-free` | OpenCode-Zen |
| `opencode-zen/nemotron-3-ultra-free` | OpenCode-Zen |
| `opencode-zen/big-pickle` | OpenCode-Zen |

**Strategy:** `auto` — benchmarks all models, routes to fastest healthy one.

### Add Your Own Models (API Keys)
```bash
# Via OmniRoute dashboard (port 20128)
open http://localhost:20128

# Or via CLI
omniroute provider add openrouter --api-key sk-or-xxx
omniroute model add openrouter/anthropic/claude-3.5-sonnet
omniroute combo add my-combo --strategy auto --models openrouter/anthropic/claude-3.5-sonnet,oc/deepseek-v4-flash-free
hermes config set model.default my-combo
```

---

## Updating from Upstream

After forking and going private:

```bash
cd .devcontainer && make update-deps
# Review changes
git diff .devcontainer/
# Commit if satisfied
git add -A && git commit -m "Update .devcontainer from upstream"
```

**What `make update-deps` does:**
- Clones upstream to temp directory
- `rsync`s `.devcontainer/` (excludes hidden files like `.git/`, `.env`)
- Preserves your custom files

---

## Local Development Alternative

Prefer running locally? See **[hermes-webtop](https://github.com/gitricko/hermes-webtop)** — Docker-based setup for your own machine with the same stack + Linux WebTop

---

## Troubleshooting

### View Setup Logs
```bash
code /tmp/hermes-codespace.log    # Full setup log
tail -f /tmp/hermes-codespace.log # Follow live
```

### Service Logs
```bash
tail -f /tmp/modelrelay.log
tail -f /tmp/omniroute.log
tail -f /tmp/ollama.log
tail -f ~/.hermes/logs/gateway.log
tail -f ~/.hermes/logs/dashboard.log
```

### Health Check
```bash
.devcontainer/self-check.sh
# Outputs JSON report to /tmp/health-report.json
# Exit codes: 0=OK, 1=warnings, 2=critical failures
```

### Common Issues

| Issue | Fix |
|-------|-----|
| Ports not showing | Wait 1–2 min; check `post-start-cmd.sh` logs |
| OmniRoute no models | `omniroute combo list` → ensure `auto-fastest` exists |
| Hermes "model not found" | `hermes config get model.default` → should be `auto-fastest` |
| Mnemon not working | `mnemon --version` → should show `0.1.17` |
| Disk full | Run `.devcontainer/free-disk.sh` |

### Reset Everything (Nuclear)
```bash
# In codespace terminal
rm -rf ~/.hermes ~/.mnemon ~/.omniroute ~/.ollama
# Then rebuild codespace (Codespaces → ... → Rebuild)
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      GitHub Codespace                           │
├─────────────────────────────────────────────────────────────────┤
│  VS Code + Extensions                                           │
│  ├─ Hermes Extension (ACP)                                      │
│  ├─ Claude Code Extension                                       │
│  └─ Cline Extension                                             │
├─────────────────────────────────────────────────────────────────┤
│  Terminal Agents                                                │
│  ├─ hermes (CLI + Gateway + Dashboard)                          │
│  ├─ claude (CLI via Omniroute)                                  │
├─────────────────────────────────────────────────────────────────┤
│  Model Routers (OpenAI-compatible)                              │
│  ├─ OmniRoute  :20128  → 8 free models (auto-fastest)           │
│  ├─ ModelRelay :7352   → fallback router                        │
│  └─ Ollama     :11434  → local embeddings (nomic-embed-text)    │
├─────────────────────────────────────────────────────────────────┤
│  Memory Layer                                                   │
│  └─ Mnemon (SQLite, no token limits, persists across sessions)  │
└─────────────────────────────────────────────────────────────────┘
```

---

## File Structure

```
hermes-codespace/
├── README.md                    # This file
├── LICENSE                      # MIT License
├── .devcontainer/
│   ├── devcontainer.json        # Dev Container spec
│   ├── post-create-cmd.sh       # One-time setup (runs on create)
│   ├── post-start-cmd.sh        # Runs on every start
│   ├── start-hermes.sh          # Service startup orchestrator
│   ├── self-check.sh            # Health check (ports, models, disk, memory)
│   ├── Makefile                 # update-deps target
│   ├── free-disk.sh             # Cleanup script
│   ├── skill-memory-automation.md  # Hermes memory skill
│   ├── cline-globalState.json   # Cline preset config
│   ├── cline-secrets.json       # Cline preset secrets
│   ├── claude-term-settings.json # Claude Code settings
│   ├── .claude.json             # Claude Code global config
│   ├── CLAUDE.md                # Claude Code instructions
│   ├── .hermes.md               # Hermes user memory template
│   └── screen-shot.png          # Dashboard screenshot
└── .github/
    └── dependabot.yml           # Dependabot config for devcontainer deps
```

---

## Contributing

1. Fork → Create feature branch
2. Test in Codespace (`make update-deps` to sync)
3. Run `./self-check.sh` before committing
4. PR with clear description

---

## License

MIT — see [LICENSE](LICENSE)

---

## Credits

Built on amazing open-source projects:

- [Hermes Agent](https://github.com/NousResearch/hermes-agent) by Nous Research
- [ModelRelay](https://github.com/gitricko/modelrelay) by rolandorojas
- [OmniRoute](https://github.com/gitricko/omniroute) by diegosouzapw
- [Mnemon](https://github.com/mnemon-dev/mnemon) by mnemon-dev
- [Ollama](https://ollama.com/) by Ollama Team
- [Claude Code](https://github.com/anthropics/claude-code) by Anthropic
- [Cline](https://github.com/saoudrizwan/cline) by Saoud Rizwan

---

**Star ⭐ this repo if it saves you time!**  
**Issues & PRs welcome.**
