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

**Cause**: The web client is NOT bundled in the selkies wheel. selkies returns 404 on `/` unless `--web-root` points at a built client.

**Fix**:
1. Build the client: `cmd_build_web` (clone selkies repo → `addons/selkies-web-core` → `npm ci` → `npm run build` → copy `dist/` to `~/.selkies/web_root`).
2. Ensure `start` passes `--web-root=~/.selkies/web_root` (it does by default).
3. Verify: `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3000/` → should be `200`.

## ImportError: libva/libva-drm/libva-x11

**Cause**: pixelflux needs VA-API libraries for H.264 encoding.

**Fix**:
```bash
sudo apt-get install -y libva2 libva-drm2 libva-x11-2
```

## WebSocket 404 on /websockets/primary

**Cause**: The WebSocket path changed in newer selkies versions.

**Fix**: The correct path is `/api/websockets`, not `/websockets/primary`. Ensure the selkies `--web-root` is set correctly.

## selkies can't start on port 3000 (port in use)

**Cause**: Another process is using port 3000.

**Fix**:
```bash
sudo lsof -i :3000  # check what's using the port
# Kill the process or change SELKIES_PORT
```

## selkies can't see DISPLAY

**Cause**: DISPLAY env var not set or incorrect.

**Fix**: selkies must be started with `DISPLAY=:20` env var (the script handles this automatically):
```bash
DISPLAY=:20 ~/.selkies/venv/bin/selkies --addr=0.0.0.0 --port=3000 --mode=websockets
```

## pixelflux build fails (No CMAKE_ASM_NASM_COMPILER / missing libudev / missing libavutil)

**Cause**: pixelflux compiles Rust extensions that link against system C libraries. The error messages vary by missing dependency:
- `No CMAKE_ASM_NASM_COMPILER` → missing `nasm` (for x264 SIMD assembly)
- `Package libudev was not found` → missing `libudev-dev`
- `HINT: if you have installed the library, try setting PKG_CONFIG_PATH to the directory containing libavutil.pc` → missing ffmpeg dev packages

**Fix**: Install all build deps before `pip install`:
```bash
sudo apt-get install -y nasm cmake pkg-config libudev-dev libx264-dev \
  libturbojpeg0-dev libavcodec-dev libavformat-dev libavutil-dev \
  libswscale-dev libavfilter-dev libgbm-dev libinput-dev \
  libwayland-dev libxkbcommon-dev libegl-dev libgles-dev libclang-dev
```
Plus Rust toolchain: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y`

See the "Build deps" table in SKILL.md Prerequisites for the full list with purposes.

## pcmflux~=2.1.0 not found (Could not find a version that satisfies the requirement)

**Cause**: `selkies` requires `pcmflux~=2.1.0` (audio capture), but 2.1.0 is unreleased on PyPI (max: 2.0.0). Like pixelflux, the 2.1.0 version exists only in the selkies-project fork's git HEAD. Building from git is the only way to get it.

**Fix**: Install pcmflux from git **before** selkies:
```bash
source ~/.selkies/venv/bin/activate
pip install "git+https://github.com/selkies-project/pcmflux.git"
```

## Interrupted apt leaves dpkg broken (dpkg was interrupted)

**Cause**: Installing XFCE4 (a large package set) can hit the terminal timeout, leaving dpkg in an unconfigured state. All subsequent apt calls fail with "dpkg was interrupted".

**Fix**:
```bash
sudo DEBIAN_FRONTEND=noninteractive dpkg --configure -a
```
The `DEBIAN_FRONTEND=noninteractive` is critical — without it, `keyboard-configuration` launches an interactive debconf dialog that hangs the terminal. After this, retry `prereqs --fix`.

## Process won't die after stop

**Cause**: `setsid` spawns processes in a new session; PID tracking may miss child processes.

**Fix**:
```bash
# Force kill all selkies-related processes
~/.selkies/selkies-native.sh stop
pkill -f "pixelflux" 2>/dev/null
pkill -f "xfce4" 2>/dev/null
pkill -f "Xvfb :20" 2>/dev/null
```

## XFCE components not starting

**Cause**: Session config missing or DISPLAY not propagated.

**Fix**: Check logs:
```bash
~/.selkies/selkies-native.sh logs xfce
cat ~/.xsession-errors  # if it exists
DISPLAY=:20 xlsclients  # should list xfwm4, xfce4-panel, xfdesktop, Thunar
```
