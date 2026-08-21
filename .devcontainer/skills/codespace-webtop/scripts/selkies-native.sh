#!/usr/bin/env bash
# selkies-native.sh — Native Selkies/XFCE webtop (browser desktop) control script
# Manages Xvfb → XFCE → selkies (pixelflux) → nginx stack
# Generic: works on any Ubuntu/Debian base system (Codespaces, VM, bare metal)
set -uo pipefail

# ── Paths (override via env vars for portability) ──────────────────────
SCRIPT_DIR="${SELKIES_SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
VENV_DIR="${SELKIES_VENV_DIR:-$HOME/.selkies/venv}"
WHEEL_DIR="${SELKIES_WHEEL_DIR:-$SCRIPT_DIR/wheels}"
SELKIES_WHEEL="${SELKIES_WHEEL:-$WHEEL_DIR/selkies-0.0.0.dev0-py3-none-any.whl}"
NGINX_TEMPLATE="${SELKIES_NGINX_TEMPLATE:-$SCRIPT_DIR/../templates/nginx.conf.template}"
NGINX_SITE="${NGINX_SITE:-/etc/nginx/sites-enabled/selkies}"
PID_DIR="${SELKIES_PID_DIR:-/tmp/selkies-pids}"
LOG_DIR="${SELKIES_LOG_DIR:-/tmp/selkies-logs}"
WHEEL_URL="${SELKIES_WHEEL_URL:-https://github.com/selkies-project/selkies/releases/latest/download/selkies-wheel.zip}"

# Display & ports (override via env)
XVFB_DISPLAY="${XVFB_DISPLAY:-:20}"
XVFB_SCREEN="${XVFB_SCREEN:-1920x1080x24}"
SELKIES_ADDR="${SELKIES_ADDR:-127.0.0.1}"
SELKIES_PORT="${SELKIES_PORT:-8082}"
SELKIES_FRAMERATE="${SELKIES_FRAMERATE:-30}"
NGINX_PORT="${NGINX_PORT:-3000}"
# Web client root (built by cmd_build_web during install)
WEB_ROOT="${SELKIES_WEB_ROOT:-$HOME/.selkies/web_root}"

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

  if ! sudo -n true 2>/dev/null; then
    echo "[install] WARNING: passwordless sudo not available."
    echo "          Commands requiring root will prompt for password."
    echo "          If sudo is not available, install apt deps manually."
  fi

  echo "[apt] updating package list..."
  sudo apt-get update -qq

  echo "[apt] installing system dependencies..."
  sudo apt-get install -y -qq \
    xvfb xfce4 xfce4-goodies dbus-x11 \
    nginx python3-venv python3-pip \
    libva2 libva-drm2 libva-x11-2 \
    curl 2>&1 | tail -5

  # Virtualenv
  echo "[venv] creating at $VENV_DIR"
  python3 -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install --quiet --no-cache-dir --upgrade pip wheel

  # Install selkies wheel (pixelflux + pcmflux pulled from PyPI as deps)
  if [[ ! -f "$SELKIES_WHEEL" ]]; then
    echo "[wheel] vendored wheel not found at $SELKIES_WHEEL"
    cmd_download_wheel
  fi

  # Reliable fallback: build the wheel from the selkies git source.
  # PyPI selkies==1.6.1 is the legacy GStreamer package (wrong).
  # The GitHub Actions selkies-wheel artifact needs auth (401) and the
  # releases/latest download URL is dead, so building from git is the
  # only path that works unattended on a fresh install.
  if [[ ! -f "$SELKIES_WHEEL" ]]; then
    echo "[wheel] download failed — building wheel from git source..."
    "$VENV_DIR/bin/pip" wheel --no-cache-dir \
      --wheel-dir "$(dirname "$SELKIES_WHEEL")" \
      "git+https://github.com/selkies-project/selkies.git" 2>&1 | tail -5
    local built
    built="$(find "$(dirname "$SELKIES_WHEEL")" -name 'selkies-*.whl' -print -quit 2>/dev/null)"
    [[ -n "$built" ]] && SELKIES_WHEEL="$built"
  fi

  if [[ ! -f "$SELKIES_WHEEL" ]]; then
    echo "[wheel] ERROR: selkies wheel not available"
    echo "        See SKILL.md for manual build from git source"
    return 1
  fi

  echo "[pip] installing pixelflux, pcmflux, and selkies wheel..."
  "$VENV_DIR/bin/pip" install --no-cache-dir \
    pixelflux pcmflux \
    "$SELKIES_WHEEL"

  # Build and install selkies web frontend from addons/selkies-web-core
  echo "[web] building selkies-web-core (vite)..."
  cmd_build_web

  # Install nginx config template (substitute placeholders)
  echo "[nginx] installing config to $NGINX_SITE"
  local tmp_conf="/tmp/selkies-nginx-$$.conf"
  sed \
    -e "s/NGINX_PORT_PLACEHOLDER/$NGINX_PORT/" \
    -e "s/SELKIES_ADDR_PLACEHOLDER/$SELKIES_ADDR/" \
    -e "s/SELKIES_PORT_PLACEHOLDER/$SELKIES_PORT/" \
    "$NGINX_TEMPLATE" > "$tmp_conf"
  sudo cp "$tmp_conf" "$NGINX_SITE"
  sudo nginx -t >/dev/null 2>&1 || { echo "[nginx] config test failed"; return 1; }
  rm -f "$tmp_conf"

  # Mark as installed
  mkdir -p "$PID_DIR"
  touch "$PID_DIR/.installed"

  echo "=== install complete ==="
}

# Download selkies wheel from GitHub Actions artifact
cmd_download_wheel() {
  if ! command -v curl >/dev/null 2>&1; then
    echo "[wheel] curl required for download"
    return 1
  fi

  echo "[wheel] downloading from GitHub Actions..."
  local tmpzip="/tmp/selkies-wheel-$$.zip"
  curl -sL "$WHEEL_URL" -o "$tmpzip"
  if [[ ! -s "$tmpzip" ]]; then
    echo "[wheel] download failed"
    rm -f "$tmpzip"
    return 1
  fi

  # Extract the wheel from the zip
  local tmpdir="/tmp/selkies-extract-$$"
  mkdir -p "$tmpdir"
  unzip -o -q "$tmpzip" -d "$tmpdir" 2>/dev/null || true
  local wheel="$(find "$tmpdir" -name 'selkies-*.whl' -print -quit 2>/dev/null)"
  if [[ -n "$wheel" && -f "$wheel" ]]; then
    mkdir -p "$(dirname "$SELKIES_WHEEL")"
    cp "$wheel" "$SELKIES_WHEEL"
    echo "[wheel] extracted to $SELKIES_WHEEL"
  else
    echo "[wheel] no wheel found in archive"
    rm -rf "$tmpdir" "$tmpzip"
    return 1
  fi
  rm -rf "$tmpdir" "$tmpzip"
}

# Build selkies web frontend from addons/selkies-web-core
cmd_build_web() {
  echo "[web] building selkies-web-core..."

  local web_src="$HOME/.selkies/selkies-web-core"
  local web_dist="$HOME/.selkies/web_root"

  # Clone or update the web-core repo
  if [[ ! -d "$web_src/.git" ]]; then
    echo "[web] cloning selkies-web-core..."
    git clone --depth 1 https://github.com/selkies-project/selkies.git /tmp/selkies-full 2>/dev/null
    mkdir -p "$web_src"
    cp -r /tmp/selkies-full/addons/selkies-web-core/* "$web_src/"
    rm -rf /tmp/selkies-full
  else
    echo "[web] updating existing clone..."
    (cd "$web_src" && git pull --depth 1) 2>/dev/null || true
  fi

  # Install deps and build with Vite
  (cd "$web_src" && npm ci --no-audit --no-fund >/dev/null 2>&1) || {
    echo "[web] npm ci failed, trying npm install..."
    (cd "$web_src" && npm install --no-audit --no-fund 2>&1 | tail -3)
  }
  (cd "$web_src" && npm run build 2>&1 | tail -5)

  # Copy built dist to web_root (where selkies will serve from)
  mkdir -p "$web_dist"
  cp -r "$web_src/dist/"* "$web_dist/"

  echo "[web] built and copied to $web_dist"
  ls -la "$web_dist/"
}

# ── start: Xvfb → XFCE → selkies → nginx ───────────────────────────────
cmd_start() {
  echo "=== selkies-native: start ==="

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
  while ! curl -s -o /dev/null -w "%{http_code}" "http://$SELKIES_ADDR:$SELKIES_PORT/" 2>/dev/null | grep -q "200\|302"; do
    [[ $i -ge 30 ]] && { echo "[selkies] health check timeout"; return 1; }
    sleep 0.5
    ((i++))
  done
  echo "[selkies] HTTP ready"

  # 4. nginx
  echo "[nginx] starting on port $NGINX_PORT"
  sudo nginx -t >/dev/null 2>&1 || { echo "[nginx] config test failed"; return 1; }
  sudo nginx 2>&1 | grep -v "invalid PID" || true
  sleep 1

  echo "=== selkies-native started ==="
  echo "  Access: forward port $NGINX_PORT → open in browser"
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
  echo "[nginx] stopping"
  sudo nginx -s quit 2>/dev/null || sudo pkill -f "nginx.*master" 2>/dev/null || true
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
  echo -n "[nginx] "
  if sudo nginx -t >/dev/null 2>&1 && (ss -tlnp 2>/dev/null | grep -q ":$NGINX_PORT" || netstat -tlnp 2>/dev/null | grep -q ":$NGINX_PORT"); then
    echo "RUNNING (port $NGINX_PORT)"
  else
    echo "STOPPED"
  fi
  echo ""
  echo "Ports:"
  ss -tlnp 2>/dev/null | grep -E ":($NGINX_PORT|$SELKIES_PORT)" 2>/dev/null || netstat -tlnp 2>/dev/null | grep -E ":($NGINX_PORT|$SELKIES_PORT)" 2>/dev/null || true
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
[[ -x "$SCRIPT_DIR/selkies-native.sh" ]] && { $hook_cmd } &>/dev/null &
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
  install            Install system deps, create venv, install selkies+pixelflux+pcmflux, build web client, nginx config
  start              Start Xvfb → XFCE → selkies → nginx (selkies serves built web client via --web-root)
  stop               Stop all components cleanly
  restart            Stop then start
  status             Show PID/health of each component
  autostart          {enable|disable|status} — hook into shell rc file
  prereqs [--fix]    Check (and optionally install) system dependencies
  logs [component]   Show tail of logs (xvfb/xfce/selbies/nginx or 'all')

Environment overrides:
  SELKIES_VENV_DIR     Venv path (default: ~/.selkies/venv)
  SELKIES_PORT         selkies internal port (default: 8082)
  NGINX_PORT           Public port (default: 3000)
  SELKIES_WEB_ROOT     Web client root dir (default: ~/.selkies/web_root, built at install)
  XVFB_DISPLAY         X11 display (default: :20)
  XVFB_SCREEN          Screen resolution (default: 1920x1080x24)

Architecture:
  Browser (port $NGINX_PORT) → nginx → selkies ($SELKIES_ADDR:$SELKIES_PORT, mode=websockets)
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
