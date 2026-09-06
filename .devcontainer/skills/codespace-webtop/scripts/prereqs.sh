#!/usr/bin/env bash
# prereqs.sh — Check (and optionally install) system dependencies for codespace-webtop.
# Idempotent: re-running is a no-op when everything is present.
set -u

FIX=0
[[ "${1:-}" == "--fix" ]] && FIX=1

ok()   { printf '  \033[32mOK\033[0m   %s\n' "$1"; }
info() { printf '  \033[36mINFO\033[0m %s\n' "$1"; }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAILED=1; }

FAILED=0

echo "=== codespace-webtop: prereqs ==="

# 1. OS check (Ubuntu/Debian only)
OS_ID=$(grep '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")
if [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "debian" ]]; then
    ok "OS: $OS_ID (apt-based)"
else
    fail "OS: $OS_ID — this skill supports Ubuntu/Debian only"
fi

# 2. sudo
if sudo -n true 2>/dev/null; then
    ok "sudo (passwordless)"
elif [[ $FIX -eq 1 ]]; then
    info "sudo requires password — will prompt during apt-get"
else
    warn "sudo (may require password)"
fi

# 3. python3 + pip3
if command -v python3 >/dev/null 2>&1; then
    PY_VER=$(python3 -c 'import sys; print(".".join(map(str,sys.version_info[:2])))')
    ok "python3 $PY_VER"
else
    fail "python3 MISSING"
fi
if command -v pip3 >/dev/null 2>&1; then
    ok "pip3 present"
else
    fail "pip3 MISSING"
fi

# 4. apt packages
APT_PACKAGES=(xvfb xfce4 xfce4-goodies dbus-x11 nginx python3-venv python3-pip libva2 libva-drm2 libva-x11-2)
MISSING_APT=()
for pkg in "${APT_PACKAGES[@]}"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        ok "$pkg present"
    else
        if [[ $FIX -eq 1 ]]; then
            MISSING_APT+=("$pkg")
        else
            fail "$pkg MISSING"
        fi
    fi
done

if [[ ${#MISSING_APT[@]} -gt 0 ]]; then
    info "Installing missing apt packages: ${MISSING_APT[*]}"
    sudo apt-get update -qq && sudo apt-get install -y -qq "${MISSING_APT[@]}" || { fail "apt-get install failed"; }
fi

# 5. Verify Xvfb, XFCE, nginx versions
for cmd in Xvfb xfce4-session nginx; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "$cmd: $(command -v "$cmd")"
    else
        fail "$cmd MISSING"
    fi
done

echo ""
if [[ $FAILED -eq 0 ]]; then
    echo "=== ALL PREREQUISITES MET ==="
    exit 0
else
    echo "=== PREREQUISITES FAILED — run with --fix to auto-install ==="
    exit 1
fi
