#!/usr/bin/env bash
# selkies-native.sh — Native Selkies/XFCE webtop (browser desktop) control script
# Manages Xvfb → XFCE → selkies (pixelflux) stack
# Generic: works on any Ubuntu/Debian base system (Codespaces, VM, bare metal)
set -uo pipefail

# ── Paths (override via env vars for portability) ──────────────────────
SCRIPT_DIR="${SELKIES_SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
VENV_DIR="${SELKIES_VENV_DIR:-$HOME/.selkies/venv}"
PID_DIR="${SELKIES_PID_DIR:-/tmp/selkies-pids}"
LOG_DIR="${SELKIES_LOG_DIR:-/tmp/selkies-logs}"

# Display & ports (override via env)
XVFB_DISPLAY="${XVFB_DISPLAY:-:20}"
XVFB_SCREEN="${XVFB_SCREEN:-1920x1080x24}"
SELKIES_ADDR="${SELKIES_ADDR:-0.0.0.0}"
SELKIES_PORT="${SELKIES_PORT:-3000}"
SELKIES_FRAMERATE="${SELKIES_FRAMERATE:-30}"
# Web client root (built by cmd_build_web during install)
WEB_ROOT="${SELKIES_WEB_ROOT:-$HOME/.selkies/web_root}"
# Pinned selkies commit for web reproducibility
SELKIES_WEB_COMMIT="${SELKIES_WEB_COMMIT:-1d9b67be6f9c695f187a0509a3c1d3b3e204807b}"
# Pinned Pixelflux commit (required by selkies main; unpinnable on PyPI)
SELKIES_PIXELFLUX_COMMIT="${SELKIES_PIXELFLUX_COMMIT:-bf07c68}"
# Pinned PCMFlux commit (required by selkies main; unpinnable on PyPI)
SELKIES_PCMFLUX_COMMIT="${SELKIES_PCMFLUX_COMMIT:-d2683ef}"

# User home for session config (auto-detect)
USER_HOME="${SUDO_USER_HOME:-$HOME}"
SESSION_XML_DIR="$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
SESSION_XML="$SESSION_XML_DIR/xfce4-session.xml"
SYSTEM_SESSION_XML="/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml"
SYSTEM_SESSION_XML_NEW="${SYSTEM_SESSION_XML}.dpkg-new"

# ── Helpers ──────────────────────────────────────────────────────────
mkdir -p "$PID_DIR" "$LOG_DIR"

pid_file() { echo "$PID_DIR/$1.pid"; }
log_file() { echo "$LOG_DIR/$1.log"; }

read_pid() {
  local file="$1"
  [[ -f "$file" ]] && cat "$file" 2>/dev/null || echo ""
}

is_running() {
  local pid="$1"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

start_daemon() {
  local name="$1"; shift
  local cmd=("$@")
  local pidf="$(pid_file "$name")"
  local logf="$(log_file "$name")"

  if is_running "$(read_pid "$pidf")"; then
    echo "[$name] already running (PID $(read_pid "$pidf"))"
    return 0
  fi

  echo "[$name] starting..."
  env DISPLAY="$XVFB_DISPLAY" setsid "${cmd[@]}" >>"$logf" 2>&1 &
  local pid=$!
  echo "$pid" >"$pidf"

  sleep 0.5
  if is_running "$pid"; then
    echo "[$name] started (PID $pid)"
    return 0
  else
    echo "[$name] failed to start — see $logf"
    tail -20 "$logf" 2>/dev/null || true
    return 1
  fi
}

stop_daemon() {
  local name="$1"
  local pidf="$(pid_file "$name")"
  local pid="$(read_pid "$pidf")"

  if ! is_running "$pid"; then
    echo "[$name] not running"
    rm -f "$pidf"
    return 0
  fi

  echo "[$name] stopping (PID $pid)..."
  kill "$pid" 2>/dev/null || true
  local i=0
  while is_running "$pid" && [[ $i -lt 20 ]]; do
    sleep 0.2
    ((i++))
  done
  if is_running "$pid"; then
    echo "[$name] force killing..."
    kill -9 "$pid" 2>/dev/null || true
    sleep 0.5
  fi
  rm -f "$pidf"
  echo "[$name] stopped"
}

status_daemon() {
  local name="$1"
  local pid="$(read_pid "$(pid_file "$name")")"
  if is_running "$pid"; then
    echo "[$name] RUNNING (PID $pid)"
    return 0
  else
    echo "[$name] STOPPED"
    return 1
  fi
}

# ── install: system deps + pip selkies + pixelflux + pcmflux ───────────
cmd_install() {
  echo "=== selkies-native: install ==="

  export DEBIAN_FRONTEND=noninteractive

  if ! sudo -n true 2>/dev/null; then
    echo "[install] WARNING: passwordless sudo not available."
    echo "          Commands requiring root will prompt for password."
    echo "          If sudo is not available, install apt deps manually."
  fi

  echo "[apt] updating package list..."
  sudo apt-get update -qq

  echo "[apt] installing runtime dependencies..."
  sudo apt-get install -y -qq \
    xvfb xfce4 xfce4-goodies dbus-x11 \
    python3-venv python3-pip \
    libva2 libva-drm2 libva-x11-2 \
    curl 2>&1 | tail -5

  echo "[apt] installing build dependencies for pixelflux/pcmflux..."
  sudo apt-get install -y -qq \
    nasm cmake pkg-config \
    libudev-dev libx264-dev libturbojpeg0-dev \
    libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libavfilter-dev \
    libgbm-dev libinput-dev libwayland-dev libxkbcommon-dev \
    libegl-dev libgles-dev libclang-dev libpixman-1-dev libdrm-dev \
    2>&1 | tail -5

  # Rust toolchain (required for pixelflux/pcmflux PyO3 builds)
  # Only set rust_installed_by_us=1 if WE install it. If the user already
  # has a rustup toolchain (even if not on PATH), we must NOT delete it
  # during cleanup.
  local rust_installed_by_us=0
  if ! command -v cargo &>/dev/null && [[ ! -d "$HOME/.cargo" && ! -d "$HOME/.rustup" ]]; then
    echo "[rust] installing Rust toolchain..."
    rust_installed_by_us=1
    # Download rustup-init binary + verify sha256 instead of curl | sh
    local arch="$(uname -m)"
    local dl_base="https://static.rust-lang.org/rustup/dist/${arch}-unknown-linux-gnu"
    if ! curl -sSf "${dl_base}/rustup-init.sha256" -o /tmp/rustup-init.sha256; then
      echo "[rust] ERROR: could not fetch rustup checksum"
      return 1
    fi
    curl -sSf "${dl_base}/rustup-init" -o /tmp/rustup-init || {
      echo "[rust] ERROR: could not download rustup-init"
      return 1
    }
    # Verify checksum before executing. Note: this detects accidental
    # corruption or a mirror with corrupted data, but does not address a
    # compromised distribution origin — if static.rust-lang.org itself is
    # serving a malicious binary with a matching forged checksum, the
    # executable still runs with the installer's privileges. The checksum
    # comparison assumes the download channel (HTTPS) provides transport
    # integrity against accidental corruption; supply-chain risk is
    # out-of-scope for this installer and applies equally to all package
    # managers (npm, pip, cargo, apt).
    ( cd /tmp && grep -q "rustup-init" rustup-init.sha256 \
      && echo "$(awk '{print $1}' rustup-init.sha256)  rustup-init" | sha256sum -c - ) || {
      echo "[rust] ERROR: rustup-init checksum verification failed"
      return 1
    }
    chmod +x /tmp/rustup-init
    /tmp/rustup-init -y --default-toolchain stable
    rm -f /tmp/rustup-init /tmp/rustup-init.sha256
    source "$HOME/.cargo/env"
  elif command -v cargo &>/dev/null; then
    echo "[rust] already installed ($(rustc --version))"
  else
    echo "[rust] existing rustup found on disk (not on PATH), reusing"
    source "$HOME/.cargo/env" 2>/dev/null || true
  fi

  # Virtualenv
  echo "[venv] creating at $VENV_DIR"
  python3 -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install --quiet --no-cache-dir --upgrade pip wheel

  # Install selkies from git source.
  # PyPI selkies==1.6.1 is the legacy GStreamer package (wrong).
  # selkies main branch requires pixelflux~=2.1.0 and pcmflux~=2.1.0,
  # which are unreleased on PyPI (max: 2.0.0). The 2.1.0 versions exist
  # only in git HEAD. Pins to specific commits for reproducibility — update
  # these SHAs when upstream changes, via env vars or direct edit.
  echo "[pip] installing pixelflux, pcmflux, and selkies from pinned git..."
  "$VENV_DIR/bin/pip" install --no-cache-dir \
    "git+https://github.com/selkies-project/pixelflux.git@${SELKIES_PIXELFLUX_COMMIT}" \
    "git+https://github.com/selkies-project/pcmflux.git@${SELKIES_PCMFLUX_COMMIT}" \
    "git+https://github.com/selkies-project/selkies.git@${SELKIES_WEB_COMMIT}" || {
    echo "[pip] ERROR: failed to install pixelflux/pcmflux/selkies from git"
    return 1
  }

  # Verify selkies is importable
  if ! "$VENV_DIR/bin/python" -c "import selkies" 2>/dev/null; then
    echo "[pip] ERROR: selkies installed but not importable"
    return 1
  fi

  # Build and install selkies web frontend (selkies-dashboard + embedded core)
  echo "[web] building selkies-dashboard web client..."
  cmd_build_web || return 1

  # ── Cleanup: remove build-time-only artifacts to save disk ──────────
  # Rust toolchain + cargo registry are only needed during pip install
  # (pixelflux/pcmflux compile Rust → .so). After that, only the
  # compiled extensions in the venv are needed at runtime.
  local before_kb after_kb saved_mb
  before_kb=$(du -sk "$HOME/.rustup" "$HOME/.cargo" "$HOME/.selkies/selkies-src" "$HOME/.cache/pip" 2>/dev/null \
    | awk '{s+=$1} END{print s+0}')

  echo "[cleanup] removing Rust toolchain (build-time only, ~1.5GB)..."
  if [[ "$rust_installed_by_us" -eq 1 ]]; then
    rm -rf "$HOME/.rustup" "$HOME/.cargo"
  else
    echo "[cleanup] Rust was pre-existing, skipping removal"
    # Only clean the cargo build cache, not the toolchain
    rm -rf "$HOME/.cargo/registry/cache" "$HOME/.cargo/registry/src" "$HOME/.cargo/git/db"
  fi

  echo "[cleanup] removing selkies source clone (web dist already copied)..."
  rm -rf "$HOME/.selkies/selkies-src"

  echo "[cleanup] removing pip cache..."
  rm -rf "$HOME/.cache/pip"

  after_kb=$(du -sk "$HOME/.rustup" "$HOME/.cargo" "$HOME/.selkies/selkies-src" "$HOME/.cache/pip" 2>/dev/null \
    | awk '{s+=$1} END{print s+0}')
  saved_mb=$(( (before_kb - after_kb) / 1024 ))
  echo "[cleanup] freed ~${saved_mb}MB"

  # Mark as installed
  mkdir -p "$PID_DIR"
  touch "$PID_DIR/.installed"

  echo "=== install complete ==="
}

# Build selkies web frontend.
# CRITICAL: serve selkies-dashboard, NOT selkies-web-core.
# selkies-web-core is only the embeddable streaming Core: it mounts with the
# sidebar CLOSED and only opens on a toggleDashboard postMessage, so serving it
# alone gives a desktop feed with NO sidebar chrome. selkies-dashboard is the
# standalone UI (sidebar + Core embedded); its copy-core.js prebuild pulls
# ../selkies-web-core/dist/selkies-core.js, so both addons must be siblings
# under one cloned repo. Build web-core first, then dashboard, serve dashboard dist.
cmd_build_web() {
  echo "[web] building selkies web client (dashboard + embedded core)..."

  local repo_dir="$HOME/.selkies/selkies-src"
  local web_core_dir="$repo_dir/addons/selkies-web-core"
  local dashboard_dir="$repo_dir/addons/selkies-dashboard"
  local web_dist="$WEB_ROOT"

  # Clone full selkies repo once (both addons must be siblings).
  # Pin to the same commit as the Python package for reproducibility.
  # Uses the global SELKIES_WEB_COMMIT env var (can be overridden externally).
  if [[ ! -d "$repo_dir/.git" ]]; then
    echo "[web] cloning selkies (full repo, both addons needed)..."
    rm -rf "$repo_dir"
    if ! git clone --depth 1 https://github.com/selkies-project/selkies.git "$repo_dir" 2>&1 | tail -3; then
      echo "[web] ERROR: git clone failed"
      return 1
    fi
    # Checkout the pinned commit
    (cd "$repo_dir" && git checkout -q "$SELKIES_WEB_COMMIT") || {
      echo "[web] ERROR: failed to checkout commit $SELKIES_WEB_COMMIT"
      return 1
    }
  else
    echo "[web] updating existing clone to pinned commit..."
    (cd "$repo_dir" && git fetch --depth 1 origin "$SELKIES_WEB_COMMIT" && git checkout -q "$SELKIES_WEB_COMMIT") 2>/dev/null || {
      echo "[web] ERROR: failed to update to pinned commit $SELKIES_WEB_COMMIT"
      return 1
    }
  fi

  build_addon() {
    local dir="$1"
    echo "[web] npm build in $dir ..."
    if ! ( cd "$dir" && { npm ci --no-audit --no-fund 2>/dev/null || npm install --no-audit --no-fund; } && npm run build ) 2>&1 | tail -8; then
      echo "[web] ERROR: npm build failed in $dir"
      return 1
    fi
  }

  # web-core first (dashboard prebuild imports its dist), then dashboard
  if ! build_addon "$web_core_dir"; then
    return 1
  fi
  if ! build_addon "$dashboard_dir"; then
    return 1
  fi

  # Serve the DASHBOARD dist (has the sidebar + embeds the Core)
  mkdir -p "$web_dist"
  rm -rf "$web_dist"/* 2>/dev/null || true
  if ! cp -r "$dashboard_dir/dist/"* "$web_dist/"; then
    echo "[web] ERROR: failed to copy dashboard dist"
    return 1
  fi

  echo "[web] built and copied dashboard to $web_dist"
  ls -la "$web_dist/"
}

# ── start: Xvfb → XFCE → selkies ─────────────────────────────────────
cmd_start() {
  echo "=== selkies-native: start ==="

  # 0. Kill legacy nginx if port $SELKIES_PORT is occupied (from old skill installs).
  #    nginx used to proxy port 3000 → selkies; now selkies binds directly.
  #    Don't rely on ss -tlnp process names — unprivileged ss omits them for
  #    root-owned processes. Instead, check if anything occupies our port and
  #    attempt a graceful nginx stop. If nginx isn't running, the stop is a no-op.
  #    Only force-kill if the process on the port IS nginx (check via ss -tlnp
  #    with sudo to see process name). Unrelated services on the port are left alone.
  if ss -tln " sport = :$SELKIES_PORT " 2>/dev/null | grep -q ":$SELKIES_PORT"; then
    echo "[nginx] port $SELKIES_PORT occupied — stopping legacy nginx if present..."
    sudo nginx -s quit 2>/dev/null || true
    sleep 0.5
    # If port is still occupied after nginx stop, check if the remaining
    # process is nginx before force-killing
    if ss -tln " sport = :$SELKIES_PORT " 2>/dev/null | grep -q ":$SELKIES_PORT"; then
      if sudo ss -tlnp " sport = :$SELKIES_PORT " 2>/dev/null | grep -q "nginx"; then
        echo "[nginx] forcing kill of nginx on port $SELKIES_PORT..."
        sudo fuser -k "$SELKIES_PORT/tcp" 2>/dev/null || true
        sleep 0.5
      else
        echo "[nginx] WARNING: port $SELKIES_PORT occupied by non-nginx process, not killing"
        return 1
      fi
    fi
    # Remove stale selkies site config so a later nginx restart won't reload it
    [[ -f /etc/nginx/sites-enabled/selkies ]] && sudo rm -f /etc/nginx/sites-enabled/selkies
  fi

  # 1. Xvfb
  echo "[Xvfb] starting on $XVFB_DISPLAY"
  local xvfb_pid="$(read_pid "$(pid_file xvfb)")"
  if ! is_running "$xvfb_pid"; then
    pkill -f "Xvfb $XVFB_DISPLAY" 2>/dev/null || true
    sleep 0.5
    start_daemon xvfb Xvfb "$XVFB_DISPLAY" -screen 0 "$XVFB_SCREEN" -nolisten tcp
  else
    echo "[Xvfb] already running (PID $xvfb_pid)"
  fi

  # Wait for Xvfb socket
  local disp_num="${XVFB_DISPLAY#:}"
  local i=0
  while [[ ! -S "/tmp/.X11-unix/X$disp_num" ]] && [[ $i -lt 30 ]]; do
    sleep 0.2
    ((i++))
  done
  [[ -S "/tmp/.X11-unix/X$disp_num" ]] || { echo "[Xvfb] socket not ready"; return 1; }

  # 2. XFCE session
  echo "[XFCE] starting on $XVFB_DISPLAY"
  local xfce_pid="$(read_pid "$(pid_file xfce)")"
  if ! is_running "$xfce_pid"; then
    # Ensure XFCE session config exists (prevents "unable to load failsafe session")
    ensure_xfce_session_config

    pkill -f "xfce4-session" 2>/dev/null || true
    sleep 0.5

    # Export DISPLAY explicitly for dbus-launch + xfce4-session
    start_daemon xfce env DISPLAY="$XVFB_DISPLAY" dbus-launch --exit-with-session xfce4-session
  else
    echo "[XFCE] already running (PID $xfce_pid)"
  fi

  # Brief settle for XFCE
  sleep 2

  # 3. selkies
  echo "[selkies] starting on $SELKIES_ADDR:$SELKIES_PORT (mode=websockets)"
  local selkies_pid="$(read_pid "$(pid_file selkies)")"
  if ! is_running "$selkies_pid"; then
    pkill -f "selkies.*--port=$SELKIES_PORT" 2>/dev/null || true
    sleep 0.5
    # SECURITY: --enable-basic-auth=false is intentional. In a Codespace the
    # public port is gated by GitHub's authenticated port-forward, so the
    # desktop is not exposed to the open internet. On a bare-metal/VM host where
    # the port is publicly routed, keep it private or put selkies behind an
    # authenticating proxy (selkies basic-auth is a single shared credential).
    DISPLAY="$XVFB_DISPLAY" start_daemon selkies \
      "$VENV_DIR/bin/selkies" \
      --addr="$SELKIES_ADDR" \
      --port="$SELKIES_PORT" \
      --mode=websockets \
      --web-root="$WEB_ROOT" \
      --enable-basic-auth=false \
      --framerate="$SELKIES_FRAMERATE"
  else
    echo "[selkies] already running (PID $selkies_pid)"
  fi

  # Wait for selkies HTTP
  local i=0
  while ! curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$SELKIES_PORT/" 2>/dev/null | grep -q "200\|302"; do
    [[ $i -ge 30 ]] && { echo "[selkies] health check timeout"; return 1; }
    sleep 0.5
    ((i++))
  done
  echo "[selkies] HTTP ready"

  echo "=== selkies-native started ==="
  echo "  Access: forward port $SELKIES_PORT → open in browser"
}

# Ensure XFCE session XML exists, copy from system default if missing
ensure_xfce_session_config() {
  if [[ -f "$SESSION_XML" ]]; then
    return 0
  fi

  # Find source XML (try .dpkg-new first, then plain)
  local source_xml=""
  if [[ -f "$SYSTEM_SESSION_XML_NEW" ]]; then
    source_xml="$SYSTEM_SESSION_XML_NEW"
  elif [[ -f "$SYSTEM_SESSION_XML" ]]; then
    source_xml="$SYSTEM_SESSION_XML"
  fi

  if [[ -z "$source_xml" ]]; then
    echo "[XFCE] WARNING: no system session XML found, creating minimal config"
    mkdir -p "$SESSION_XML_DIR"
    cat > "$SESSION_XML" <<'XEOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-session" version="1.0">
  <property name="general" type="empty">
    <property name="FailsafeSessionName" type="string" value="Failsafe"/>
  </property>
  <property name="sessions" type="empty">
    <property name="Failsafe" type="empty">
      <property name="IsFailsafe" type="bool" value="true"/>
      <property name="Count" type="int" value="5"/>
      <property name="Client0_Command" type="array">
        <value type="string" value="xfwm4"/>
      </property>
      <property name="Client0_Priority" type="int" value="15"/>
      <property name="Client0_PerScreen" type="bool" value="false"/>
      <property name="Client1_Command" type="array">
        <value type="string" value="xfsettingsd"/>
      </property>
      <property name="Client1_Priority" type="int" value="20"/>
      <property name="Client1_PerScreen" type="bool" value="false"/>
      <property name="Client2_Command" type="array">
        <value type="string" value="xfce4-panel"/>
      </property>
      <property name="Client2_Priority" type="int" value="25"/>
      <property name="Client2_PerScreen" type="bool" value="false"/>
      <property name="Client3_Command" type="array">
        <value type="string" value="Thunar"/>
        <value type="string" value="--daemon"/>
      </property>
      <property name="Client3_Priority" type="int" value="30"/>
      <property name="Client3_PerScreen" type="bool" value="false"/>
      <property name="Client4_Command" type="array">
        <value type="string" value="xfdesktop"/>
      </property>
      <property name="Client4_Priority" type="int" value="35"/>
      <property name="Client4_PerScreen" type="bool" value="false"/>
    </property>
  </property>
</channel>
XEOF
  else
    mkdir -p "$SESSION_XML_DIR"
    cp "$source_xml" "$SESSION_XML"
  fi

  # Fix ownership (may be running as root with SUDO_USER set)
  local target_user="${SUDO_USER:-}"
  if [[ -n "$target_user" ]]; then
    chown -R "$target_user:$target_user" "$(dirname "$SESSION_XML_DIR")" 2>/dev/null || true
  else
    chown -R "$(whoami):$(whoami)" "$(dirname "$SESSION_XML_DIR")" 2>/dev/null || true
  fi
}

# ── stop: clean shutdown all ───────────────────────────────────────────
cmd_stop() {
  echo "=== selkies-native: stop ==="
  stop_daemon selkies
  stop_daemon xfce
  stop_daemon xvfb
  echo "=== selkies-native stopped ==="
}

# ── restart ────────────────────────────────────────────────────────────
cmd_restart() {
  cmd_stop
  sleep 1
  cmd_start
}

# ── status ─────────────────────────────────────────────────────────────
cmd_status() {
  echo "=== selkies-native status ==="
  status_daemon xvfb || true
  status_daemon xfce || true
  status_daemon selkies || true
  echo ""
  echo "Ports:"
  ss -tlnp 2>/dev/null | grep ":$SELKIES_PORT" 2>/dev/null || netstat -tlnp 2>/dev/null | grep ":$SELKIES_PORT" 2>/dev/null || true
}

# ── autostart: idempotent hook ────────────────────────────────────────
cmd_autostart() {
  local action="${1:-}"
  local rc_file="$HOME/.bashrc"
  local zshrc="$HOME/.zshrc"
  local hook_marker="# selkies-native autostart"
  local hook_cmd="$SCRIPT_DIR/selkies-native.sh start"

  # Detect which rc file exists, prefer the first found
  local target_rc=""
  for rc in "$rc_file" "$zshrc"; do
    [[ -f "$rc" ]] && target_rc="$rc" && break
  done
  [[ -z "$target_rc" ]] && target_rc="$rc_file"

  case "$action" in
    enable)
      echo "[autostart] enabling in $target_rc"
      if ! grep -q "$hook_marker" "$target_rc" 2>/dev/null; then
        cat >> "$target_rc" <<EOF

$hook_marker
[[ -x "$SCRIPT_DIR/selkies-native.sh" ]] && { $hook_cmd; } &>/dev/null &
EOF
        echo "[autostart] enabled (appended to $target_rc)"
      else
        echo "[autostart] already enabled"
      fi
      ;;
    disable)
      echo "[autostart] disabling in $target_rc"
      sed -i "/$hook_marker/d; /selkies-native.sh start/d" "$target_rc"
      echo "[autostart] disabled"
      ;;
    status)
      if grep -q "$hook_marker" "$target_rc" 2>/dev/null; then
        echo "[autostart] enabled in $target_rc"
      else
        echo "[autostart] disabled"
      fi
      ;;
    *)
      echo "Usage: selkies-native.sh autostart {enable|disable|status}"
      return 1
      ;;
  esac
}

# ── logs ──────────────────────────────────────────────────────────────
cmd_logs() {
  local component="${1:-all}"
  if [[ "$component" == "all" ]]; then
    for f in "$LOG_DIR"/*.log; do
      [[ -f "$f" ]] && echo "=== $f ===" && tail -20 "$f"
    done
  elif [[ -f "$LOG_DIR/$component.log" ]]; then
    tail -f "$LOG_DIR/$component.log"
  else
    echo "No log file for '$component'. Available: $(ls "$LOG_DIR"/*.log 2>/dev/null | xargs -n1 basename 2>/dev/null | tr '\n' ' ')"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: selkies-native.sh {install|start|stop|restart|status|autostart|logs} [args]

Commands:
  install            Install system deps + Rust, create venv, install selkies+pixelflux+pcmflux from git, build web client
  start              Start Xvfb → XFCE → selkies (serves built web client via --web-root)
  stop               Stop all components cleanly
  restart            Stop then start
  status             Show PID/health of each component
  autostart          {enable|disable|status} — hook into shell rc file
  prereqs [--fix]    Check (and optionally install) system dependencies
  logs [component]   Show tail of logs (xvfb/xfce/selkies or 'all')

Environment overrides:
  SELKIES_VENV_DIR     Venv path (default: ~/.selkies/venv)
  SELKIES_ADDR         Bind address (default: 0.0.0.0)
  SELKIES_PORT         Port (default: 3000)
  SELKIES_WEB_ROOT     Web client root dir (default: ~/.selkies/web_root, built at install)
  XVFB_DISPLAY         X11 display (default: :20)
  XVFB_SCREEN          Screen resolution (default: 1920x1080x24)

Architecture:
  Browser (port $SELKIES_PORT) → selkies ($SELKIES_ADDR:$SELKIES_PORT, mode=websockets)
  selkies drives pixelflux capture on Xvfb $XVFB_DISPLAY running XFCE
EOF
}

main() {
  case "${1:-}" in
    install)    cmd_install ;;
    start)      cmd_start ;;
    stop)       cmd_stop ;;
    restart)    cmd_restart ;;
    status)     cmd_status ;;
    autostart)  cmd_autostart "${2:-}" ;;
    prereqs)    bash "$SCRIPT_DIR/prereqs.sh" "${2:-}" ;;
    logs)       cmd_logs "${2:-all}" ;;
    -h|--help|help) usage ;;
    *)          usage; return 1 ;;
  esac
}

main "$@"
