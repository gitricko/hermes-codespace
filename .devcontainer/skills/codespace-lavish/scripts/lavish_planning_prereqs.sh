#!/usr/env bash
# lavish_planning_prereqs.sh — verify everything the lavish-planning-gui skill needs.
#
# The skill NEVER assumes the Codespace is pre-provisioned. This script checks each
# requirement and, with --fix, installs what is missing. Fail-closed: any missing
# REQUIRED item => exit 1.
#
# Checks (each PASS/FAIL):
#   1. Xvfb            (virtual display)
#   2. openbox         (window manager)
#   3. x11vnc          (RFB export of :99)
#   4. websockify      (VNC->websocket bridge)
#   5. novnc web assets(/usr/share/novnc)
#   6. Browser binary  (google-chrome-stable | chromium | chromium-browser)
#   7. node + npm      (lavish-axi runtime)
#   8. lavish-axi      (resolvable via npx, or on PATH)
#
# Usage: lavish_planning_prereqs.sh [--fix]
#   --fix installs the missing apt packages and (re)resolves lavish-axi via npx.
# Exit code: 0 if all REQUIRED checks pass, 1 otherwise.

set -u
FIX=0
[[ "${1:-}" == "--fix" ]] && FIX=1

pass=0; fail=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
fixed(){ printf '  \033[32mFIXED\033[0m %s\n' "$1"; if [[ $fail -gt 0 ]]; then fail=$((fail-1)); fi; }
info() { printf '  \033[36mINFO\033[0m %s\n' "$1"; }

echo "lavish-planning-gui prerequisite check"
echo ""

echo "[1] Xvfb (virtual display)"
if command -v Xvfb >/dev/null 2>&1; then
  ok "Xvfb present"
else
  bad "Xvfb missing"
  if [[ $FIX -eq 1 ]]; then
    info "attempting apt-get install -y xvfb"
    if (sudo -n true 2>/dev/null && sudo apt-get install -y xvfb) >/dev/null 2>&1 || apt-get install -y xvfb >/dev/null 2>&1; then
      fixed "Xvfb installed via apt"
    else
      bad "Xvfb install failed (need apt + root/sudo)"
    fi
  else
    info "rerun with --fix to install (apt-get install -y xvfb)"
  fi
fi

echo "[2] openbox (window manager)"
if command -v openbox >/dev/null 2>&1; then
  ok "openbox present"
else
  bad "openbox missing"
  if [[ $FIX -eq 1 ]]; then
    info "attempting apt-get install -y openbox"
    if (sudo -n true 2>/dev/null && sudo apt-get install -y openbox) >/dev/null 2>&1 || apt-get install -y openbox >/dev/null 2>&1; then
      fixed "openbox installed via apt"
    else
      bad "openbox install failed (need apt + root/sudo)"
    fi
  else
    info "rerun with --fix to install (apt-get install -y openbox)"
  fi
fi

echo "[3] x11vnc (RFB export of :99)"
if command -v x11vnc >/dev/null 2>&1; then
  ok "x11vnc present"
else
  bad "x11vnc missing"
  if [[ $FIX -eq 1 ]]; then
    info "attempting apt-get install -y x11vnc"
    if (sudo -n true 2>/dev/null && sudo apt-get install -y x11vnc) >/dev/null 2>&1 || apt-get install -y x11vnc >/dev/null 2>&1; then
      fixed "x11vnc installed via apt"
    else
      bad "x11vnc install failed (need apt + root/sudo)"
    fi
  else
    info "rerun with --fix to install (apt-get install -y x11vnc)"
  fi
fi

echo "[4] websockify (VNC->websocket bridge)"
if command -v websockify >/dev/null 2>&1; then
  ok "websockify present"
else
  bad "websockify missing"
  if [[ $FIX -eq 1 ]]; then
    info "attempting apt-get install -y websockify"
    if (sudo -n true 2>/dev/null && sudo apt-get install -y websockify) >/dev/null 2>&1 || apt-get install -y websockify >/dev/null 2>&1; then
      fixed "websockify installed via apt"
    else
      bad "websockify install failed (need apt + root/sudo)"
    fi
  else
    info "rerun with --fix to install (apt-get install -y websockify)"
  fi
fi

echo "[5] noVNC web assets (/usr/share/novnc)"
if [[ -d /usr/share/novnc && -f /usr/share/novnc/vnc.html ]]; then
  ok "noVNC assets present"
else
  bad "noVNC web assets missing at /usr/share/novnc"
  if [[ $FIX -eq 1 ]]; then
    info "attempting apt-get install -y novnc"
    if (sudo -n true 2>/dev/null && sudo apt-get install -y novnc) >/dev/null 2>&1 || apt-get install -y novnc >/dev/null 2>&1; then
      fixed "novnc installed via apt (assets at /usr/share/novnc)"
    else
      bad "novnc install failed (need apt + root/sudo)"
    fi
  else
    info "rerun with --fix to install (apt-get install -y novnc)"
  fi
fi

echo "[6] Browser binary (google-chrome-stable | chromium | chromium-browser)"
BROWSER_BIN="$(command -v google-chrome-stable || command -v chromium || command -v chromium-browser)"
if [[ -n "$BROWSER_BIN" ]]; then
  ok "browser: $BROWSER_BIN"
else
  bad "no browser binary found (google-chrome-stable/chromium/chromium-browser)"
  if [[ $FIX -eq 1 ]]; then
    info "installing Google Chrome stable .deb (Ubuntu 24.04 has no chromium apt deb)"
    TMP_DEB="$(mktemp /tmp/chrome-XXXX.deb)"
    if curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -o "$TMP_DEB" 2>/dev/null; then
      if (sudo -n true 2>/dev/null && sudo apt-get install -y "$TMP_DEB") >/dev/null 2>&1 || apt-get install -y "$TMP_DEB" >/dev/null 2>&1; then
        # protect from free-disk.sh autoremove
        sudo -n true 2>/dev/null && sudo apt-mark manual google-chrome-stable >/dev/null 2>&1 || apt-mark manual google-chrome-stable >/dev/null 2>&1 || true
        fixed "google-chrome-stable installed"
      else
        bad "google-chrome-stable .deb install failed (need apt + root/sudo)"
      fi
      rm -f "$TMP_DEB"
    else
      bad "failed to download google-chrome-stable .deb"
    fi
  else
    info "rerun with --fix to install Google Chrome (Ubuntu 24.04 ships no chromium deb)"
  fi
fi

echo "[7] node + npm (lavish-axi runtime)"
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  ok "node $(node -v 2>&1) / npm $(npm -v 2>&1)"
else
  bad "node and/or npm missing"
  if [[ $FIX -eq 1 ]]; then
    info "node/npm are NOT auto-installed by this script (environment-specific: apt/nvm/volta). Install node >=18 then re-run."
  else
    info "install node >=18 (apt/nvm/volta), then re-run prereqs"
  fi
fi

echo "[8] lavish-axi (resolvable via npx, or on PATH)"
if command -v lavish-axi >/dev/null 2>&1; then
  ok "lavish-axi on PATH ($(lavish-axi --version 2>&1 | head -1))"
else
  # not on PATH — can npx resolve it on demand? (no install yet; just probe cache)
  if [[ -d ~/.npm/_npx ]] && find ~/.npm/_npx -maxdepth 4 -type d -path "*lavish-axi/dist" 2>/dev/null | head -1 | grep -q .; then
    ok "lavish-axi resolvable via npx cache"
  else
    bad "lavish-axi not on PATH and not in npx cache"
    if [[ $FIX -eq 1 ]]; then
      info "resolving lavish-axi via 'npx --yes lavish-axi --version' (downloads if needed)"
      if timeout 120 npx --yes lavish-axi --version >/dev/null 2>&1; then
        fixed "lavish-axi resolved via npx"
      else
        bad "npx lavish-axi failed (needs network + node/npm)"
      fi
    else
      info "rerun with --fix to resolve via npx (npx --yes lavish-axi)"
    fi
  fi
fi

echo ""
if [[ $fail -eq 0 ]]; then
  echo -e "RESULT: \033[32mALL REQUIRED PREREQUISITES MET\033[0m — skill ready to run."
  exit 0
else
  echo -e "RESULT: \033[31m$fail REQUIRED CHECK(S) FAILED\033[0m — run with --fix, or install manually."
  exit 1
fi
