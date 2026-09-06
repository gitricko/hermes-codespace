# Selkies Native Desktop — Troubleshooting

## "Unable to load a failsafe session" popup

**Cause**: XFCE session config missing at `~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml`. Without this file, `xfce4-session` doesn't know which clients to start (xfwm4, xfce4-panel, xfdesktop, Thunar), so it shows a failsafe error.

**Fix**: The control script (`selkies-native.sh start`) auto-creates this config by:
1. Copying from `/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml.dpkg-new`
2. Falling back to a minimal inline config if the system file is missing

**Manual fix**:
```bash
mkdir -p ~/.config/xfce4/xfconf/xfce-perchannel-xml/
cp /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml{,.dpkg-new} \
   ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml
```

## selkies wheel not found

**Cause**: The PyPI `selkies==1.6.1` is the wrong package (legacy GStreamer/WebRTC, no pixelflux). The GitHub Actions `selkies-wheel` artifact needs auth (401 unauthenticated) and the `releases/latest/download/selkies-wheel.zip` URL is dead (404).

**Fix**: Build the wheel from git source — this is what `cmd_install` does as its fallback:
```bash
~/.selkies/venv/bin/pip wheel --no-cache-dir --wheel-dir ~/.hermes/skills/codespace/selkies-native-desktop/scripts/wheels "git+https://github.com/selkies-project/selkies.git"
```
This produces `selkies-0.0.0.dev0-py3-none-any.whl` (editable dev version). Then `install` picks it up automatically.

If you already have a wheel, drop it in `scripts/wheels/` and it will be used (the `.gitignore` there keeps it out of git).

**The skill no longer ships vendored wheels** — they are built at install time. This keeps the skill repo lean (~15KB vs ~80MB).

## selkies serves 404 on `/` but WS connects

**Cause**: The web client is NOT bundled in the selkies wheel. selkies returns 404 on `/` unless `--web-root` points at a built client. nginx proxies `/` to selkies, so you get a 404 page in the browser even though the WebSocket at `/api/websockets` may work.

**Fix**:
1. Build the client: `cmd_build_web` (clone selkies repo → `addons/selkies-web-core` → `npm ci` → `npm run build` → copy `dist/` to `~/.selkies/web_root`).
2. Ensure `start` passes `--web-root=~/.selkies/web_root` (it does by default).
3. Verify: `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8082/` → should be `200`.

## ImportError: libva/libva-drm/libva-x11

**Cause**: pixelflux needs VA-API libraries for H.264 encoding.

**Fix**:
```bash
sudo apt-get install -y libva2 libva-drm2 libva-x11-2
```

## WebSocket 404 on /websockets/primary

**Cause**: The WebSocket path changed in newer selkies versions.

**Fix**: The correct path is `/api/websockets`, not `/websockets/primary`. Ensure nginx config proxies WebSocket upgrade to the right path (the template handles this correctly).

## Nginx not starting on port 3000

**Cause**: Port already in use, or Codespaces port visibility not set to `public`.

**Fix**:
```bash
sudo nginx -s stop  # if nginx is already running
sudo lsof -i :3000  # check what's using the port
# In Codespaces: set port 3000 to public in VS Code Ports panel
```

## selkies can't see DISPLAY

**Cause**: DISPLAY env var not set or incorrect.

**Fix**: selkies must be started with `DISPLAY=:20` env var:
```bash
DISPLAY=:20 ~/.selkies/venv/bin/selkies --addr=127.0.0.1 --port=8082 --mode=websockets
```

## Process won't die after stop

**Cause**: `setsid` spawns processes in a new session; PID tracking may miss child processes.

**Fix**:
```bash
# Force kill all selkies-related processes
~/.selkies/selkies-native.sh stop
pkill -f "pixelflux" 2>/dev/null
pkill -f "xfce4" 2>/dev/null
pkill -f "Xvfb :20" 2>/dev/null
sudo nginx -s quit 2>/dev/null
```

## XFCE components not starting

**Cause**: Session config missing or DISPLAY not propagated.

**Fix**: Check logs:
```bash
~/.selkies/selkies-native.sh logs xfce
cat ~/.xsession-errors  # if it exists
DISPLAY=:20 xlsclients  # should list xfwm4, xfce4-panel, xfdesktop, Thunar
```
