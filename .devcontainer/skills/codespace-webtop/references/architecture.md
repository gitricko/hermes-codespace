# Selkies Native Desktop — Architecture

## Stack Overview

```
Browser (port 3000, GitHub auth) → selkies (0.0.0.0:3000, mode=websockets)
  selkies drives pixelflux capture on Xvfb :20 running XFCE
  pixelflux: Rust X11 capture → H.264/JPEG stripes → WebSocket
```

## Components

| Component | Process | Port | Purpose |
|-----------|---------|------|---------|
| Xvfb | `Xvfb :20` | — | Headless X11 display (1920x1080x24) |
| XFCE | `xfce4-session` | — | Desktop environment (window manager, panel, file manager) |
| selkies | `selkies` | 0.0.0.0:3000 | Serves React client + WebSocket media/input protocol |
| pixelflux | (Rust .so) | — | X11 screen capture → H.264/JPEG stripes |

## Data Flow

1. **Video capture**: pixelflux hooks X11 at display :20, captures screen changes, encodes as H.264 (CPU) or JPEG stripes
2. **WebSocket streaming**: selkies multiplexes video + input + clipboard + files + settings over a single WebSocket at `/api/websockets`
3. **Browser client**: selkies serves the bundled React dashboard (sidebar with clipboard, file upload/download, keyboard, fullscreen, settings)
4. **Input injection**: browser sends mouse/keyboard events via WebSocket → selkies → xdotool/pynput → X11
5. **Auto-resize**: client-side `ResizeObserver` detects browser window size → sends resize event → selkies triggers Xvfb resolution change via xrandr

## No WebRTC/UDP

`--mode=websockets` ensures selkies uses pure WebSocket (TCP). No WebRTC, no UDP, no STUN/ICE. Works through any HTTP proxy that supports WebSocket.

## Port Forwarding

- **Codespaces**: forward port 3000 (nginx public port)
- **Local**: connect directly to `http://localhost:3000`

## File Layout

```
~/.selkies/
├── venv/          # Python venv with selkies + pixelflux + pcmflux
├── web_root/      # Built React dashboard (copied at install)
└── pid/           # PID files (xvfb, xfce, selkies)
```

## Logs

- Xvfb:      `/tmp/selkies-logs/xvfb.log`
- XFCE:      `/tmp/selkies-logs/xfce.log`
- selkies:   `/tmp/selkies-logs/selkies.log`

## Migration: Legacy nginx Cleanup

The original architecture used nginx as a reverse proxy (`3000 → 127.0.0.1:8082`). The current architecture binds selkies directly to `0.0.0.0:3000`. On upgrades, the `start` command handles legacy artifacts:

1. **Port check** — If port 3000 (or `$SELKIES_PORT`) is occupied, attempt graceful nginx stop via `nginx -s quit`.
2. **Force cleanup** — If port remains occupied, use `fuser -k` to kill the occupying process.
3. **Config removal** — Delete `/etc/nginx/sites-enabled/selkies` so a later nginx restart won't reload the stale proxy config.

This ensures clean migration from old installations without affecting unrelated nginx instances on the same host.
