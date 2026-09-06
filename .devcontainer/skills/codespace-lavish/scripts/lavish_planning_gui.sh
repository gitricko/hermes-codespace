#!/usr/bin/env bash
# lavish_planning_gui.sh — "planning lavish": bring up a headed Lavish-AXI whiteboard
# on a virtual display, bridge it to noVNC, and start the feedback poll so the user
# can iterate. Self-installing: verifies prerequisites and (with --fix) installs them.
#
# Usage:
#   lavish_planning_gui.sh [--fix] [artifact.html]
#   lavish_planning_gui.sh [--fix] --prompt "Plan the Q3 launch"
#
# Behavior:
#   - If an artifact.html path is given, open it.
#   - Else if --prompt is given, generate a planning artifact HTML from it.
#   - Else generate a default planning artifact.
# The skill NEVER assumes the Codespace is pre-provisioned; --fix installs deps.
#
# Session key = SHA256(realpath(artifact))[:16] (REQ-LAVISH-GUI-WHITEBOARD-001 §9.2).
# Chrome loads http://127.0.0.1:4387/session/<key> on DISPLAY=:99.
#
# For future agents: this script is the single entry point. It handles:
#   1. Prerequisite installation (--fix)
#   2. Full VNC stack startup (Xvfb, openbox, Chrome, x11vnc, websockify/noVNC)
#   3. Lavish-AXI engine startup
#   4. Artifact session creation
#   5. Continuous poll loop with auto-restart (survives script exit)
#   6. noVNC URL output with auto-connect + scaling

set -euo pipefail

SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PREREQS="$SELF_DIR/lavish_planning_prereqs.sh"
DISPLAY_NUM=99
LAVISH_PORT="${LAVISH_PORT:-4387}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
XVFB_SCREEN="${XVFB_SCREEN:-1280x800x24}"
CHROME_USER_DATA_DIR="/tmp/chrome-gui"
STATE_DIR="${STATE_DIR:-$HOME/.lavish-axi/slot-default}"
PROMPT=""
ARTIFACT=""
FIX=0

# Parse args: --fix, --prompt "value", --monitor, or positional artifact.html
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[i]}" in
    --fix) FIX=1 ;;
    --prompt) PROMPT="${args[i+1]:-}"; ((i++)) ;;
    --monitor) MONITOR=1 ;;
    -*) : ;;  # ignore unknown flags
    *)  # positional: artifact path
        if [[ -z "$ARTIFACT" ]]; then ARTIFACT="${args[i]}"; fi
        ;;
  esac
done

echo "=== [lavish-planning-gui] prerequisite check ==="
if [[ -x "$PREREQS" ]]; then
  if [[ $FIX -eq 1 ]]; then
    bash "$PREREQS" --fix || { echo "[lavish-planning-gui] PREREQS FAILED even after --fix; abort." >&2; exit 1; }
  else
    bash "$PREREQS" || { echo "[lavish-planning-gui] PREREQS MISSING — re-run with --fix to install." >&2; exit 1; }
  fi
else
  echo "[lavish-planning-gui] WARNING: prereqs script not found at $PREREQS" >&2
fi

# --- Resolve artifact ---
if [[ -z "$ARTIFACT" ]]; then
  if [[ -n "$PROMPT" ]]; then
    ARTIFACT="$SELF_DIR/generated-plan-$(date +%s).html"
    echo "[lavish-planning-gui] generating planning artifact from prompt: $PROMPT"
    cat > "$ARTIFACT" <<HTML
<!doctype html><html><head><meta charset="utf-8"><title>Planning — Lavish</title>
<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
<style>body{background:#0d1117;color:#e6edf3;font-family:system-ui,sans-serif;padding:2rem}
h1{color:#58a6ff}.mermaid{background:#161b22;padding:1rem;border-radius:8px}</style></head>
<body><h1>Planning Board</h1>
<p><b>Prompt:</b> ${PROMPT}</p>
<div class="mermaid">graph TD; A[Start] --> B[Elaborate]; B --> C[Review in Lavish]; C --> D[Ship]</div>
<script>mermaid.initialize({startOnLoad:true});</script></body></html>
HTML
  else
    ARTIFACT="$SELF_DIR/lavish-gui-sample.html"
    echo "[lavish-planning-gui] no artifact/prompt — using bundled sample"
  fi
fi

if [[ ! -f "$ARTIFACT" ]]; then
  echo "[lavish-planning-gui] ERROR: artifact not found: $ARTIFACT" >&2
  exit 1
fi

# --- Derive session key (exact one-liner from §9.2) ---
SESSION_KEY=$(node -e "
  const crypto = require('crypto');
  const fs = require('fs');
  console.log(crypto.createHash('sha256').update(fs.realpathSync(process.argv[1])).digest('hex').slice(0,16))
" "$ARTIFACT")
SESSION_URL="http://127.0.0.1:${LAVISH_PORT}/session/${SESSION_KEY}"
echo "[lavish-planning-gui] session key: ${SESSION_KEY}"
echo "[lavish-planning-gui] session URL: ${SESSION_URL}"

# --- Resolve lavish-axi dist (npx on the fly; never assume pre-installed) ---
LAVISH_DIST=""
if command -v lavish-axi >/dev/null 2>&1; then
  LAVISH_DIST="$(dirname "$(command -v lavish-axi)")/../lib/node_modules/lavish-axi/dist"
fi
if [[ ! -f "$LAVISH_DIST/cli.mjs" ]]; then
  echo "[lavish-planning-gui] resolving lavish-axi via npx (may download)..."
  timeout 180 npx --yes lavish-axi --version >/dev/null 2>&1 || true
  LAVISH_DIST="$(find ~/.npm/_npx -maxdepth 4 -type d -path '*lavish-axi/dist' 2>/dev/null | head -1)"
fi
if [[ -z "$LAVISH_DIST" || ! -f "$LAVISH_DIST/cli.mjs" ]]; then
  echo "[lavish-planning-gui] ERROR: could not resolve lavish-axi dist" >&2
  exit 1
fi
echo "[lavish-planning-gui] lavish-axi dist: $LAVISH_DIST"

# --- 1. Xvfb :99 ---
if ! pgrep -f "Xvfb :${DISPLAY_NUM}" >/dev/null; then
  echo "[lavish-planning-gui] starting Xvfb :${DISPLAY_NUM}..."
  Xvfb ":${DISPLAY_NUM}" -screen 0 "${XVFB_SCREEN}" -nolisten tcp >/tmp/xvfb${DISPLAY_NUM}.log 2>&1 &
  for i in {1..10}; do DISPLAY=":${DISPLAY_NUM}" xdpyinfo >/dev/null 2>&1 && break; sleep 0.5; done
else
  echo "[lavish-planning-gui] Xvfb :${DISPLAY_NUM} already running"
fi

# --- 2. openbox ---
if ! pgrep -f "openbox" >/dev/null; then
  echo "[lavish-planning-gui] starting openbox..."
  DISPLAY=":${DISPLAY_NUM}" openbox >/tmp/openbox${DISPLAY_NUM}.log 2>&1 &
  sleep 1
else
  echo "[lavish-planning-gui] openbox already running"
fi

# --- 3. Browser (headed, on :99, at Lavish session) ---
BROWSER_BIN="$(command -v google-chrome-stable || command -v chromium || command -v chromium-browser)"
if [[ -z "$BROWSER_BIN" ]]; then
  echo "[lavish-planning-gui] ERROR: no browser binary (prereq check should have caught this)" >&2
  exit 1
fi
# kill any prior instance with our data-dir so we reload cleanly
for pid in $(pgrep -x chrome 2>/dev/null); do
  if tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null | grep -q "user-data-dir=${CHROME_USER_DATA_DIR}"; then kill "$pid" 2>/dev/null; fi
done
sleep 1
echo "[lavish-planning-gui] starting ${BROWSER_BIN} on :${DISPLAY_NUM} -> ${SESSION_URL}"
DISPLAY=":${DISPLAY_NUM}" "${BROWSER_BIN}" \
  --no-sandbox --disable-gpu --disable-software-rasterizer --disable-dev-shm-usage \
  --disable-gpu-sandbox --disable-gpu-compositing --disable-accelerated-2d-canvas \
  --disable-accelerated-video-decode --disable-webgl --use-gl=swiftshader \
  --user-data-dir="${CHROME_USER_DATA_DIR}" --new-window "${SESSION_URL}" \
  >/tmp/chrome-gui.log 2>&1 &
sleep 2
# Verify Chrome is actually running
if ! pgrep -x chrome >/dev/null 2>&1; then
  echo "[lavish-planning-gui] WARNING: Chrome may have failed to start, check /tmp/chrome-gui.log" >&2
  cat /tmp/chrome-gui.log 2>/dev/null | head -20
fi

# --- 4. x11vnc ---
if ! pgrep -f "x11vnc.*:${DISPLAY_NUM}" >/dev/null; then
  echo "[lavish-planning-gui] starting x11vnc on :${DISPLAY_NUM} (rfb 5900)..."
  x11vnc -display ":${DISPLAY_NUM}" -nopw -forever -listen 127.0.0.1 -rfbport 5900 >/tmp/x11vnc.log 2>&1 &
  sleep 1
else
  echo "[lavish-planning-gui] x11vnc already running"
fi

# --- 5. websockify + noVNC ---
if ! pgrep -f "websockify.*${NOVNC_PORT}" >/dev/null; then
  echo "[lavish-planning-gui] starting websockify on 0.0.0.0:${NOVNC_PORT} -> localhost:5900..."
  websockify --web /usr/share/novnc "0.0.0.0:${NOVNC_PORT}" localhost:5900 >/tmp/websockify.log 2>&1 &
  sleep 1
else
  echo "[lavish-planning-gui] websockify already running on ${NOVNC_PORT}"
fi

# --- 6. Lavish-AXI engine on LAVISH_PORT ---
if ! curl -s -m3 "http://127.0.0.1:${LAVISH_PORT}/health" >/dev/null 2>&1; then
  echo "[lavish-planning-gui] starting lavish-axi engine on :${LAVISH_PORT}..."
  mkdir -p "$STATE_DIR"
  LAVISH_AXI_PORT="$LAVISH_PORT" LAVISH_AXI_STATE_DIR="$STATE_DIR" LAVISH_AXI_NO_OPEN=1 \
    nohup node "$LAVISH_DIST/cli.mjs" server --port "$LAVISH_PORT" >/tmp/lavish-server.log 2>&1 &
  for i in {1..20}; do curl -s -m3 "http://127.0.0.1:${LAVISH_PORT}/health" >/dev/null 2>&1 && break; sleep 0.5; done
  # Verify it's actually responding with ok
  if ! curl -s -m3 "http://127.0.0.1:${LAVISH_PORT}/health" | grep -q '"ok":true'; then
    echo "[lavish-planning-gui] ERROR: lavish-axi started but health check failed" >&2
    exit 1
  fi
else
  echo "[lavish-planning-gui] lavish-axi already up on :${LAVISH_PORT}"
fi

# --- 7. Open artifact session (creates /session/<key>) ---
echo "[lavish-planning-gui] opening session for $ARTIFACT"
( cd "$LAVISH_DIST" && LAVISH_AXI_PORT="$LAVISH_PORT" LAVISH_AXI_STATE_DIR="$STATE_DIR" LAVISH_AXI_NO_OPEN=1 \
  node "$LAVISH_DIST/cli.mjs" "$ARTIFACT" --no-open ) >/dev/null 2>&1 || true

# --- 8. Poll listener (feedback loop) — left running in background with auto-restart ---
echo "[lavish-planning-gui] starting poll listener (continuous feedback loop)..."
(
  cd "$LAVISH_DIST"
  while true; do
    LAVISH_AXI_PORT="$LAVISH_PORT" LAVISH_AXI_STATE_DIR="$STATE_DIR" \
      node "$LAVISH_DIST/cli.mjs" poll "$ARTIFACT" >>/tmp/lavish-poll.log 2>&1
    echo "[$(date)] poll exited, restarting in 2s..." >>/tmp/lavish-poll.log
    sleep 2
  done
) &
POLL_PID=$!
# Ensure it's in its own process group so it survives shell exit
disown -h $POLL_PID 2>/dev/null || true

# --- Summary ---
CODESPACE_NAME="${CODESPACE_NAME:-$(hostname)}"
# noVNC URL with auto-connect and local scaling (scale mode)
NOVNC_URL="https://${CODESPACE_NAME}-${NOVNC_PORT}.app.github.dev/vnc.html?autoconnect=true&resize=scale"
echo ""
echo "[lavish-planning-gui] =============================================="
echo "[lavish-planning-gui] Planning Lavish is LIVE"
echo "[lavish-planning-gui] =============================================="
echo "[lavish-planning-gui] Artifact : $ARTIFACT"
echo "[lavish-planning-gui] Session  : $SESSION_URL"
echo "[lavish-planning-gui] noVNC    : $NOVNC_URL"
echo "[lavish-planning-gui]   (set port ${NOVNC_PORT} to PRIVATE for auth-gated access)"
echo "[lavish-planning-gui] poll PID : $POLL_PID (continuous feedback loop active)"
echo "[lavish-planning-gui] poll log : /tmp/lavish-poll.log"
echo "[lavish-planning-gui] =============================================="

# --- Cleanup function for graceful shutdown ---
cleanup() {
  echo "[lavish-planning-gui] Received signal, cleaning up..."
  # Only kill our poll process if it's still our child
  if kill -0 "$POLL_PID" 2>/dev/null; then
    kill "$POLL_PID" 2>/dev/null || true
  fi
  exit 0
}
trap cleanup SIGTERM SIGINT

# --- Monitor mode: tail the poll log for live feedback ---
if [[ "${MONITOR:-0}" -eq 1 ]]; then
  echo "[lavish-planning-gui] Monitor mode: tailing poll log (Ctrl+C to exit)..."
  echo "[lavish-planning-gui] Feedback will appear here as user interacts with the whiteboard."
  tail -f /tmp/lavish-poll.log
fi
