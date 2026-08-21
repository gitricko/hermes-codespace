---
name: codespace-webtop
description: Native Selkies/XFCE webtop (browser desktop) via pixelflux-based selkies package — install, run, and autostart on any Ubuntu base system
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [selkies, xfce, webtop, desktop, codespaces, vnc-alternative, browser-desktop]
    related_skills: [codespace-port-visibility, github-codespace]
---

# codespace-webtop

Run a **native Selkies/XFCE webtop (browser desktop)** on any Ubuntu-based system (Codespaces, VMs, bare metal) using the official pixelflux-based `selkies` Python package — not the legacy PyPI `selkies==1.6.1` (GStreamer/WebRTC).

Matches what `linuxserver/webtop:ubuntu-xfce` provides in Docker, but runs natively on the host.

## Architecture

```
Browser (port 3000) → nginx → selkies (127.0.0.1:8082, mode=websockets)
  selkies drives pixelflux capture on Xvfb :20 running XFCE
  pixelflux: Rust X11 capture → H.264/JPEG stripes → WebSocket
```

## When to Use

- User wants a remote desktop in browser (Codespaces, SSH, VPN)
- Need clipboard sync, file upload/download, keyboard input, auto-resize
- Pure WebSocket (no WebRTC/UDP) — works behind corporate firewalls
- Auto-start on boot/reboot via systemd or shell hook

## Prerequisites

| Component | Purpose | Check |
|-----------|---------|-------|
| `ubuntu` / `debian` base | apt package manager | `lsb_release -is` |
| `sudo` | install system deps | `sudo -n true` |
| `python3` + `pip3` | selkies venv | `python3 --version` |
| `nginx` | reverse proxy + WS upgrade | `nginx -v` |
| `Xvfb` | headless X11 server | `Xvfb -version` |
| `xfce4` + `xfce4-goodies` | desktop environment | `xfce4-session --version` |
| `dbus-x11` | session bus | `dbus-daemon --version` |
| `libva2 libva-drm2 libva-x11-2` | H.264 encoding (pixelflux) | `dpkg -l libva2` |

## Quick Start

```bash
# 1. Check prerequisites (auto-install with --fix)
./scripts/selkies-native.sh prereqs --fix

# 2. Install system deps + selkies
./scripts/selkies-native.sh install

# 3. Start desktop
./scripts/selkies-native.sh start
# Forward port 3000 → open in browser → Selkies sidebar visible

# 4. Enable autostart (idempotent)
./scripts/selkies-native.sh autostart enable
```

## Commands

| Command | Description |
|---------|-------------|
| `prereqs [--fix]` | Check (and optionally install) system dependencies |
| `install` | Create venv, install selkies wheel + deps, deploy nginx config |
| `start` | Xvfb → XFCE → selkies → nginx (all via PID tracking) |
| `stop` | Clean shutdown all components |
| `restart` | stop + start |
| `status` | Show PID/health of each component |
| `autostart enable\|disable\|status` | Wire/remove hook into `~/.bashrc` or systemd |
| `logs [component\|all]` | Tail logs (xvfb, xfce, selkies, nginx) |

## Procedure

### 1. Prerequisites Check (`prereqs`)

```bash
# Check only
./scripts/prereqs.sh

# Auto-install missing apt packages
./scripts/prereqs.sh --fix
```

Validates: OS, sudo, python3, pip3, and all apt packages listed above.

### 2. Install (`install`)

1. Creates venv at `~/.selkies/venv` (or `$SELKIES_VENV_DIR`)
2. Acquires the pixelflux-based `selkies` wheel. **Order matters** — none of these are vendored, all are obtained at install time:
   - **(a)** Use a vendored `selkies-0.0.0.dev0-py3-none-any.whl` if present in `wheels/`
   - **(b)** Try `cmd_download_wheel` (GitHub Actions `selkies-wheel` artifact) — NOTE this needs auth and usually 401s, so treat as best-effort
   - **(c)** **Reliable fallback: build from git source** — `pip wheel git+https://github.com/selkies-project/selkies.git`. This is the only path that works unattended on a fresh Codespace. (PyPI `selkies==1.6.1` is the WRONG legacy GStreamer package; the `releases/latest` wheel URL is dead.)
3. **Build the web client** (`cmd_build_web`): clone selkies repo, copy `addons/selkies-web-core/`, run `npm ci` (fallback `npm install`) then `npm run build`, copy `dist/` → `~/.selkies/web_root`. The web client is **NOT** bundled in the wheel — selkies serves a 404 on `/` unless `--web-root` points at a built client.
4. Deploys nginx config (template with placeholder substitution) to `/etc/nginx/sites-enabled/selkies`
5. Validates `nginx -t`

**Note**: The skill no longer ships vendored wheels in `scripts/wheels/` (they're built at install time). A `.gitignore` in `scripts/` keeps any local wheels out of git.

### 3. Start (`start`)

Order of operations:
1. **Xvfb :20** — `Xvfb :20 -screen 0 1920x1080x24 -nolisten tcp`
2. **XFCE session** — `DISPLAY=:20 dbus-launch --exit-with-session xfce4-session`
   - Auto-creates `~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml` from system default if missing (prevents "unable to load failsafe session")
3. **selkies** — `DISPLAY=:20 selkies --addr=127.0.0.1 --port=8082 --mode=websockets --web-root=~/.selkies/web_root --enable-basic-auth=false --framerate=30`
   - `--web-root` MUST point at the built web client (`~/.selkies/web_root`, produced by `cmd_build_web` at install). Without it selkies returns **404 on `/`** and the proxy has no UI to serve.
4. **nginx** — `nginx` (proxies 3000 → 127.0.0.1:8082 with WS upgrade)

Each component tracked via PID file in `/tmp/selkies-pids/`.

### 4. Autostart (`autostart enable`)

Idempotent hook into shell rc file:
- Appends to `~/.bashrc` (or `~/.zshrc`) a guarded block that runs `selkies-native.sh start &`
- Disable removes the hook cleanly

## Configuration

Environment variables (all optional, with defaults):

| Variable | Default | Description |
|----------|---------|-------------|
| `SELKIES_VENV_DIR` | `~/.selkies/venv` | Python venv location |
| `SELKIES_PORT` | `8082` | selkies internal port |
| `SELKIES_ADDR` | `127.0.0.1` | selkies bind address |
| `NGINX_PORT` | `3000` | nginx public port |
| `XVFB_DISPLAY` | `:20` | Xvfb display number |
| `XVFB_SCREEN` | `1920x1080x24` | Screen resolution |
| `SELKIES_FRAMERATE` | `30` | Capture framerate |
| `SELKIES_WHEEL_URL` | (vendored) | URL to download selkies wheel if not local |

## Pitfalls

- **Wrong selkies package**: PyPI `selkies==1.6.1` is legacy GStreamer/WebRTC (`selkies_gstreamer`). Must use pixelflux-based `selkies` from GitHub Actions `selkies-wheel` artifact (console script is `selkies`, has `--mode=websockets`, bundles React client in `selkies_web/`).
- **Missing libva**: pixelflux needs `libva2 libva-drm2 libva-x11-2` for H.264. Without them, `import pixelflux` fails.
- **XFCE failsafe session popup**: XFCE needs `~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml`. Auto-created from system default on first start.
- **DISPLAY not propagated**: `dbus-launch` loses `DISPLAY` unless explicitly exported: `env DISPLAY=:20 dbus-launch ...`
- **WebSocket path**: selkies serves WS at `/api/websockets` (NOT `/websockets/primary` which 404s).
- **Port conflicts**: Default ports 8082 (selkies) and 3000 (nginx) must be free.
- **CI lint gate (repo `.devcontainer/skills/**`)**: Before committing any change to this skill, run `bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh`. Markdown URLs MUST be wrapped in angle brackets `<https://...>` or they fail `MD034/no-bare-urls` (this broke the initial PR #3 — two bare URLs in a References block).
- **selkies wheel acquisition is NOT plug-and-play**: The GitHub Actions artifact (`selkies-wheel`) requires auth (401 unauthenticated), the `releases/latest/download/selkies-wheel.zip` URL returns 404, and the PyPI package (`selkies==1.6.1`) is the wrong legacy GStreamer package. **The only reliable unattended path is `pip wheel git+https://github.com/selkies-project/selkies.git`** (built into `cmd_install` as fallback (c)). If you add a vendored wheel to `wheels/` it will be used, but the skill no longer ships one.
- **Web client is NOT bundled in the selkies wheel**: The wheel contains only the Python streaming server (`selkies.selkies_web` namespace is empty). The React/Vite client lives in `addons/selkies-web-core` in the selkies repo. `install` **must** run `cmd_build_web` (clone repo → npm install → npm run build → copy to `~/.selkies/web_root`) and `start` **must** pass `--web-root=~/.selkies/web_root`. Without this, selkies returns HTTP 404 on `/` and nginx has no UI to proxy.

## Security

**Authentication posture — intentional, not a bug.** The webtop runs selkies with `--enable-basic-auth=false`. This is deliberate:

- **In a GitHub Codespace** the public port (3000) is only reachable through GitHub's **authenticated port-forward** — unauthenticated users cannot reach it. No additional app-level auth is needed for the normal Codespace flow.
- **On a bare-metal/VM host** (the skill's other supported target), a publicly routed port with auth off means *anyone with the URL* gets full XFCE control (input, clipboard, file transfer).

**If you run this on a VM/bare-metal host:**
- Keep the forwarded port **private**, or
- Put nginx behind an authenticating reverse proxy (e.g. Authelia, OAuth2 Proxy, Cloudflare Access), or
- Enable selkies basic-auth (note: a single shared credential — weak on its own; defense-in-depth only).

Greptile flagged this as P1 on PR #41. We keep auth off by design for the Codespace case (already gated) and document the exposure for the VM case rather than flipping the default, which would break the frictionless Codespace flow.

## Verification

```bash
# Full health check
./scripts/prereqs.sh && \
./scripts/selkies-native.sh install && \
./scripts/selkies-native.sh start && \
sleep 3 && \
./scripts/selkies-native.sh status && \
curl -s http://127.0.0.1:3000/ | grep -q "selkies" && echo "HTTP OK" && \
python3 -c "
import asyncio, websockets
async def t():
    async with websockets.connect('ws://127.0.0.1:3000/api/websockets') as ws:
        await ws.send('ping')
        r = await asyncio.wait_for(ws.recv(), timeout=3)
        assert 'MODE websockets' in r
asyncio.run(t())
print('WS OK')
" && \
./scripts/selkies-native.sh stop
```

Expected: All components RUNNING, HTTP serves React client, WS handshake returns `MODE websockets`.

## Files

```
codespace-webtop/
├── SKILL.md                    # This file (frontmatter + docs)
├── scripts/
│   ├── selkies-native.sh       # Main control script (install/start/stop/restart/...)
│   └── prereqs.sh              # Prerequisites checker + auto-fix
├── templates/
│   ├── nginx.conf.template     # nginx proxy config (3000 → 8082, WS upgrade)
│   └── autostart.bashrc        # Shell hook snippet
└── references/
    ├── architecture.md         # Detailed architecture diagram
    └── troubleshooting.md      # Common issues + fixes
```

## References

- Architecture details: `references/architecture.md`
- Troubleshooting: `references/troubleshooting.md`
- PyPI selkies==1.6.1 is WRONG: <https://pypi.org/project/selkies/> (legacy GStreamer package)
- Correct pixelflux-based selkies: <https://github.com/selkies-project/selkies> (GitHub Actions `selkies-wheel` artifact)
