# Codespace Webtop — Native Selkies/XFCE Browser Desktop

## Overview

This project runs a **native Selkies/XFCE webtop (browser desktop)** inside a GitHub Codespace (or any Ubuntu/Debian host) using the official **pixelflux-based `selkies` Python package**. It matches what `linuxserver/webtop:ubuntu-xfce` provides in Docker, but runs natively on the host VM — no container-in-container.

The desktop is exposed to the browser over a **single WebSocket** (no WebRTC/UDP), behind the Codespace's GitHub-authenticated port forward. The Selkies React client provides a sidebar with clipboard sync, file upload/download, keyboard injection, fullscreen, and settings.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Browser (port 3000, GitHub auth)                            │
└──────────────────────────┬──────────────────────────────────┘
                           │ HTTPS/WS (single port)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ nginx (0.0.0.0:3000)                                        │
│   - Proxies ALL traffic → 127.0.0.1:8082                   │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ selkies server (127.0.0.1:8082)                             │
│   - --mode=websockets (no WebRTC/UDP)                      │
│   - --enable-basic-auth=false (Codespaces handles auth)    │
│   - --web-root=~/.selkies/web_root (built at install)      │
│   - Serves React client + WS media + input                 │
│   - Drives pixelflux capture on Xvfb display               │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ Xvfb :20 (1920x1080x24) → XFCE session                     │
│   pixelflux captures via X11 → H.264 (CPU) → WS frames     │
└─────────────────────────────────────────────────────────────┘
```

## Key Components

| Component | Process | Port/Display | Purpose |
|-----------|---------|--------------|---------|
| Xvfb | `Xvfb :20` | — | Headless X11 display (1920x1080x24) |
| XFCE | `xfce4-session` | — | Desktop environment (window manager, panel, file manager) |
| selkies | `selkies` | 127.0.0.1:8082 | Serves React client via `--web-root` + WebSocket media/input protocol |
| pixelflux | (Rust .so) | — | X11 screen capture → H.264/JPEG stripes |
| nginx | `nginx` | 0.0.0.0:3000 | Reverse proxy with WS upgrade |

## The Package Source Problem (Critical)

**PyPI `selkies==1.6.1` is the WRONG package.** It is the legacy `selkies_gstreamer` project:
- No pixelflux (Rust capture engine)
- No bundled React web client
- No `--mode=websockets` flag
- Console script is `selkies-gstreamer`, not `selkies`

The **correct pixelflux-based `selkies`** (v0.0.0.dev0) with:
- Real Selkies web client (React dashboard with sidebar) — **built from source at install time**
- pixelflux (Rust X11 capture → H.264/JPEG)
- `--mode=websockets` flag + `--web-root` flag
- WebSocket endpoint at `/api/websockets`
- Console script `selkies`

...is distributed as a **GitHub Actions artifact** (`selkies-wheel`) from the `selkies-project/selkies` repository. See [selkies-package-discrepancy](selkies-package-discrepancy.md) reference for the full breakdown.

### How to obtain the correct wheel

1. Go to <https://github.com/selkies-project/selkies/actions>
2. Find the latest successful `selkies-wheel` workflow run
3. Download the `selkies-wheel` artifact (a zip)
4. Extract `selkies-0.0.0.dev0-py3-none-any.whl`
5. Place it in `wheels/` (vendored) or let `selkies-native.sh install` auto-download

### Web Client Build (New in Skill)

The skill now **builds the React web client from source** during `install`:

1. Clones `addons/selkies-web-core` from the selkies repo
2. Runs `npm ci` (with `npm install` fallback) + `npm run build` (Vite)
3. Copies built `dist/` to `~/.selkies/web_root`
4. selkies serves it via `--web-root="$WEB_ROOT"`

This eliminates the ~80MB vendored wheels from git — the skill is now self-contained and reproducible on rebuild.

## System Dependencies

Beyond the standard `xvfb xfce4 xfce4-goodies dbus-x11 nginx python3-venv python3-pip`, pixelflux requires VA-API libraries for H.264 encoding:

```bash
sudo apt-get install -y libva2 libva-drm2 libva-x11-2
```

Without these, `import pixelflux` fails with a missing shared-library error.

## The XFCE Failsafe Session Fix

XFCE needs a session config at `~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml` to know which clients to start (xfwm4, xfce4-panel, xfdesktop, Thunar). Without it, `xfce4-session` launches no clients and shows **"unable to load a failsafe session"**.

The control script auto-creates this config on first start by copying from `/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml.dpkg-new` (with an inline minimal fallback).

Also critical: `dbus-launch` loses `DISPLAY` unless explicitly exported:
```bash
env DISPLAY=:20 dbus-launch --exit-with-session xfce4-session
```

## WebSocket Endpoint

Selkies serves the media/input WebSocket at **`/api/websockets`** (NOT `/websockets/primary`, which 404s). nginx must proxy the upgrade to this path:

```nginx
location / {
    proxy_pass http://127.0.0.1:8082;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_read_timeout 86400;
}
```

## Auto-Resize

The Selkies client uses a `ResizeObserver` on the browser window. When you drag-resize the browser, it sends a resize event → selkies triggers an Xvfb resolution change via `xrandr`. **No manual resolution picker** is needed (unlike noVNC/VNC).

## Two Implementations in This Repo

| Branch | Scope | Autostart | Paths |
|--------|-------|-----------|-------|
| `feat/selkies-native-desktop` (PR #2) | Codespace-specific | `start-hermes.sh` | `.devcontainer/selkies/` |
| `feat/selkies-skill` (PR #3) | Generic skill | `~/.bashrc` | `~/.selkies/` (env-overridable) |

The skill version (PR #3) is the portable one — it works on any Ubuntu/Debian base with environment-variable overrides for all paths, ports, and display.

## Verification

```bash
# HTTP serves React client
curl -s http://127.0.0.1:3000/ | grep -q "selkies"

# WebSocket handshake returns "MODE websockets"
python3 -c "
import asyncio, websockets
async def t():
    async with websockets.connect('ws://127.0.0.1:3000/api/websockets') as ws:
        await ws.send('ping')
        r = await asyncio.wait_for(ws.recv(), timeout=3)
        assert 'MODE websockets' in r
asyncio.run(t())
"
```

## Related

- Skill: `codespace-webtop` — procedural how-to (control script + prereqs)
- Reference: `selkies-package-discrepancy.md` — PyPI vs GitHub Actions wheel breakdown
- Wiki: `codespace-lavish.md` — alternative browser desktop (noVNC/VNC, not WebSocket)
- Wiki: `codespace-port-visibility.md` — port visibility automation
