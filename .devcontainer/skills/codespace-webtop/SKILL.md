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
Browser (port 3000) → selkies (0.0.0.0:3000, mode=websockets)
  selkies drives pixelflux capture on Xvfb :20 running XFCE
  pixelflux: Rust X11 capture → H.264/JPEG stripes → WebSocket
```

## When to Use

- User wants a remote desktop in browser (Codespaces, SSH, VPN)
- Need clipboard sync, file upload/download, keyboard input, auto-resize
- Pure WebSocket (no WebRTC/UDP) — works behind corporate firewalls
- Auto-start on boot/reboot via systemd or shell hook

## Prerequisites

### Runtime deps (needed by selkies at runtime)

| Component | Purpose | Check |
|-----------|---------|-------|
| `ubuntu` / `debian` base | apt package manager | `lsb_release -is` |
| `sudo` | install system deps | `sudo -n true` |
| `python3` + `pip3` | selkies venv | `python3 --version` |
| `Xvfb` | headless X11 server | `Xvfb -version` |
| `xfce4` + `xfce4-goodies` | desktop environment | `xfce4-session --version` |
| `dbus-x11` | session bus | `dbus-daemon --version` |
| `libva2 libva-drm2 libva-x11-2` | H.264 encoding (pixelflux) | `dpkg -l libva2` |

### Build deps (required to build pixelflux + pcmflux from git source)

The source install (the only reliable path) compiles Rust extensions (pixelflux, pcmflux) that link against system C libraries. **Why git source?** selkies `main` branch requires `pixelflux~=2.1.0` and `pcmflux~=2.1.0`, but these versions are unreleased — PyPI only has up to 2.0.0. The 2.1.0 versions exist in the selkies-project forks' git HEAD (their pyproject.toml says 2.1.0) but were never tagged or published. Building from git is the only way to satisfy these deps. These must be present **before** `pip install`:

| Component | Purpose | Install |
|-----------|---------|--------|
| `rustc` + `cargo` | Rust compiler for pixelflux/pcmflux | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh -s -- -y` |
| `nasm` | x264 SIMD assembly (pixelflux GPL encoder) | `sudo apt-get install -y nasm` |
| `cmake` | builds turbojpeg-sys, x264-sys from source | `sudo apt-get install -y cmake` |
| `pkg-config` | finds system .pc files during cargo build | `sudo apt-get install -y pkg-config` |
| `libudev-dev` | libudev-sys Rust crate build | `sudo apt-get install -y libudev-dev` |
| `libx264-dev` | x264-sys links against system libx264 | `sudo apt-get install -y libx264-dev` |
| `libturbojpeg0-dev` | turbojpeg-sys links against system libturbojpeg | `sudo apt-get install -y libturbojpeg0-dev` |
| `libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libavfilter-dev` | ffmpeg-sys-next links against system ffmpeg | `sudo apt-get install -y libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libavfilter-dev` |
| `libgbm-dev` | gbm-sys Rust crate build | `sudo apt-get install -y libgbm-dev` |
| `libinput-dev` | input-sys Rust crate build | `sudo apt-get install -y libinput-dev` |
| `libwayland-dev libxkbcommon-dev` | wayland crate builds | `sudo apt-get install -y libwayland-dev libxkbcommon-dev` |
| `libegl-dev libgles-dev` | EGL/GLES for smithay renderer | `sudo apt-get install -y libegl-dev libgles-dev` |
| `libclang-dev` | bindgen (Rust FFI generator) | `sudo apt-get install -y libclang-dev` |

**One-liner to install all build deps**:
```bash
# Rust toolchain
export RUSTUP_HOME=~/.rustup CARGO_HOME=~/.cargo
source ~/.cargo/env 2>/dev/null || curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && source ~/.cargo/env
# System build deps
sudo apt-get install -y nasm cmake pkg-config libudev-dev libx264-dev \
  libturbojpeg0-dev libavcodec-dev libavformat-dev libavutil-dev \
  libswscale-dev libavfilter-dev libgbm-dev libinput-dev \
  libwayland-dev libxkbcommon-dev libegl-dev libgles-dev libclang-dev
```

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
| `install` | Create venv, install selkies+pixelflux+pcmflux from git, build web client |
| `start` | Xvfb → XFCE → selkies (all via PID tracking) |
| `stop` | Clean shutdown all components |
| `restart` | stop + start |
| `status` | Show PID/health of each component |
| `autostart enable\|disable\|status` | Wire/remove hook into `~/.bashrc` or systemd |
| `logs [component\|all]` | Tail logs (xvfb, xfce, selkies) |

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
2. Installs pixelflux, pcmflux, and selkies from git source. **Why git source?** selkies `main` branch requires `pixelflux~=2.1.0` and `pcmflux~=2.1.0`, which are unreleased — PyPI only has up to 2.0.0. The 2.1.0 versions exist only in git HEAD. Building from git is the only way to satisfy these deps:
     ```bash
     source ~/.selkies/venv/bin/activate && source ~/.cargo/env
     pip install "git+https://github.com/selkies-project/pixelflux.git"
     pip install "git+https://github.com/selkies-project/pcmflux.git"
     pip install "git+https://github.com/selkies-project/selkies.git"
     ```
     (PyPI `selkies==1.6.1` is the WRONG legacy GStreamer package.)
3. **Build the web client** (`cmd_build_web`): clone the full selkies repo (both `addons/selkies-web-core` and `addons/selkies-dashboard` must be siblings), `npm install` + `npm run build` **selkies-web-core first** (the dashboard's prebuild imports its `dist/selkies-core.js`), then build **selkies-dashboard**, and copy `addons/selkies-dashboard/dist/` → `~/.selkies/web_root`. The web client is **NOT** bundled in the wheel — serve the dashboard, NOT bare web-core (see Pitfalls: bare core = no sidebar).

     **Vite build workaround**: The Hermes terminal tool may detect `npx vite build` or `./node_modules/.bin/vite` as a long-lived server and refuse to run it. Use `node ./node_modules/vite/bin/vite.js build` instead.

     **Dashboard prebuild**: `npm run build` in selkies-dashboard runs `node copy-core.js` as a prebuild hook. If using direct `node` invocation for vite, run `node copy-core.js` manually before the vite build.

**Note**: The skill no longer ships vendored wheels in `scripts/wheels/` (they're built at install time). A `.gitignore` in `scripts/` keeps any local wheels out of git.

### 3. Start (`start`)

Order of operations:
1. **Xvfb :20** — `Xvfb :20 -screen 0 1920x1080x24 -nolisten tcp`
2. **XFCE session** — `DISPLAY=:20 dbus-launch --exit-with-session xfce4-session`
   - Auto-creates `~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml` from system default if missing (prevents "unable to load failsafe session")
3. **selkies** — `DISPLAY=:20 selkies --addr=0.0.0.0 --port=3000 --mode=websockets --web-root=~/.selkies/web_root --enable-basic-auth=false --framerate=30`
   - `--web-root` MUST point at the built web client (`~/.selkies/web_root`, produced by `cmd_build_web` at install). Without it selkies returns **404 on `/`**.

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
| `SELKIES_PORT` | `3000` | Port for selkies |
| `SELKIES_ADDR` | `0.0.0.0` | Bind address |
| `XVFB_DISPLAY` | `:20` | Xvfb display number |
| `XVFB_SCREEN` | `1920x1080x24` | Screen resolution |
| `SELKIES_FRAMERATE` | `30` | Capture framerate |

## Pitfalls

- **Wrong selkies package**: PyPI `selkies==1.6.1` is legacy GStreamer/WebRTC (`selkies_gstreamer`). Must use pixelflux-based `selkies` from GitHub Actions `selkies-wheel` artifact (console script is `selkies`, has `--mode=websockets`, bundles React client in `selkies_web/`).
- **Missing libva**: pixelflux needs `libva2 libva-drm2 libva-x11-2` for H.264. Without them, `import pixelflux` fails.
- **XFCE failsafe session popup**: XFCE needs `~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml`. Auto-created from system default on first start.
- **DISPLAY not propagated**: `dbus-launch` loses `DISPLAY` unless explicitly exported: `env DISPLAY=:20 dbus-launch ...`
- **WebSocket path**: selkies serves WS at `/api/websockets` (NOT `/websockets/primary` which 404s).
- **Port conflict**: Default port 3000 must be free.
- **CI lint gate (repo `.devcontainer/skills/**`)**: Before committing any change to this skill, run `bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh`. Markdown URLs MUST be wrapped in angle brackets `<https://...>` or they fail `MD034/no-bare-urls` (this broke the initial PR #3 — two bare URLs in a References block).
- **selkies wheel acquisition is NOT plug-and-play**: The GitHub Actions artifact (`selkies-wheel`) requires auth (401 unauthenticated), the `releases/latest/download/selkies-wheel.zip` URL returns 404, and the PyPI package (`selkies==1.6.1`) is the wrong legacy GStreamer package. **The only reliable unattended path is installing all three from git** (built into `cmd_install`).
- **Web client MUST be `selkies-dashboard`, not `selkies-web-core` (this is the #1 failure mode).** The selkies repo has TWO web addons: `addons/selkies-web-core` (the embeddable streaming **Core** only, README literally says "for an external dashboard to interact with the client") and `addons/selkies-dashboard` (the standalone UI that embeds the Core). If `install` serves `selkies-web-core`, the webtop WILL launch and the desktop WILL render, but there is **NO sidebar** — the Core mounts with `_isSidebarOpen = !1` (closed) and only opens on a `toggleDashboard` window.postMessage. Symptom when this is wrong: video/audio/clipboard work fine, WS handshake returns `MODE websockets`, HTTP 200 — but the Selkies sidebar chrome (settings/stats/clipboard/files/shortcuts) is absent. Fix: build `selkies-dashboard` (its `prebuild` copies `../selkies-web-core/dist/selkies-core.js`, so both addons must be siblings under one cloned repo), then point `--web-root` at the dashboard's `dist/`. Verify by grepping the served bundle for `sidebar`/`toggle` (dashboard has ~90 `sidebar` + ~100 `toggle`; bare core has almost none and starts closed). See `references/web-client-no-sidebar.md` for the full diagnosis recipe.
- **`autostart enable` must keep `{ ...; }` with a trailing `;`**: the appended rc line is `[[ -x ... ]] && { "$SCRIPT_DIR/selkies-native.sh" start; } &>/dev/null &`. A missing `;` before `}` (i.e. `{ ... start }`) makes bash throw `syntax error: unexpected end of file` for EVERY new login shell — it silently breaks `.bashrc` and anything that sources it. The template and script both use the `;`-terminated form; if you ever regenerate the hook by hand, keep it.
- **`npm ci` fails on a fresh shallow clone**: `git clone --depth 1` may not ship a `package-lock.json` that `npm ci` requires, so `npm ci` errors and the build silently produces nothing (then the dashboard's `prebuild` aborts with "missing selkies-core.js"). Always wrap as `npm ci ... || npm install ...`, and build `selkies-web-core` BEFORE `selkies-dashboard` — dashboard's `prebuild` (`copy-core.js`) exits 1 if `../selkies-web-core/dist/selkies-core.js` is absent.
- **Interrupted apt install leaves dpkg broken**: Installing XFCE4 (a large package set) frequently hits the terminal timeout. When `prereqs --fix` fails mid-apt, `dpkg` is left in an unconfigured state and subsequent apt calls fail with "dpkg was interrupted". Fix: `sudo DEBIAN_FRONTEND=noninteractive dpkg --configure -a` before retrying. The `DEBIAN_FRONTEND=noninteractive` is critical — without it, `keyboard-configuration` launches an interactive debconf dialog that hangs the terminal.
- **pcmflux~=2.1.0 is a hidden dependency**: selkies requires `pcmflux~=2.1.0` (audio capture), but like pixelflux, 2.1.0 is unreleased on PyPI (max: 2.0.0). The git-source install must build pixelflux and pcmflux **before** selkies — pip resolves all `~=2.1.0` constraints at once, but only if the packages are already installed in the venv.

## Security

**Authentication posture — intentional, not a bug.** The webtop runs selkies with `--enable-basic-auth=false`. This is deliberate:

- **In a GitHub Codespace** the public port (3000) is only reachable through GitHub's **authenticated port-forward** — unauthenticated users cannot reach it. No additional app-level auth is needed for the normal Codespace flow.
- **On a bare-metal/VM host** (the skill's other supported target), a publicly routed port with auth off means *anyone with the URL* gets full XFCE control (input, clipboard, file transfer).

**If you run this on a VM/bare-metal host:**
- Keep the forwarded port **private**, or
- Put selkies behind an authenticating reverse proxy (e.g. Authelia, OAuth2 Proxy, Cloudflare Access), or
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
