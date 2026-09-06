# Selkies Native Desktop — Architecture

## Stack Overview

```
Browser (port 3000, GitHub auth) → nginx → selkies (127.0.0.1:8082, mode=websockets)
  selkies drives pixelflux capture on Xvfb :20 running XFCE
  pixelflux: Rust X11 capture → H.264/JPEG stripes → WebSocket
```

## Components

| Component | Process | Port | Purpose |
|-----------|---------|------|---------|
| Xvfb | `Xvfb :20` | — | Headless X11 display (1920x1080x24) |
| XFCE | `xfce4-session` | — | Desktop environment (window manager, panel, file manager) |
| selkies | `selkies` | 127.0.0.1:8082 | Serves React client + WebSocket media/input protocol |
| pixelflux | (Rust .so) | — | X11 screen capture → H.264/JPEG stripes |
| nginx | `nginx` | 0.0.0.0:3000 | Reverse proxy with WS upgrade |

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
├── wheels/        # Vendored selkies wheel (for offline install)
└── pid/           # PID files (xvfb, xfce, selkies)

/etc/nginx/sites-enabled/selkies  # nginx reverse proxy config
```

## Logs

- Xvfb:      `/tmp/selkies-logs/xvfb.log`
- XFCE:      `/tmp/selkies-logs/xfce.log`
- selkies:   `/tmp/selkies-logs/selkies.log`
- nginx:     `/var/log/nginx/error.log`
