#!/usr/bin/env bash
# codespace-cleanup.sh — Reclaim disk space in GitHub Codespaces
# Safe to re-run (idempotent). Skips anything already removed.
#
# Usage:
#   chmod +x codespace-cleanup.sh && ./codespace-cleanup.sh
#
# What it does:
#   1. Removes unused Ollama CUDA/Vulkan GPU libraries (CPU fallback)
#   2. Cleans package manager caches (pip, npm, uv, electron, node-gyp)
#   3. Removes unused language runtimes (PHP, Ruby, SDKMAN/Java)
#   4. Cleans stale VS Code server copies (biggest win: ~17G on /vscode)
#   5. Cleans stale VS Code serverCache entries
#   6. Removes unused global npm packages (cline)
#   7. Cleans nvm cache and old node versions
#   8. Removes unused tools (Hugo, buildscriptgen, Go, K8s tools)
#
# What it does NOT touch:
#   - Ollama binary or models (embeddings stay working)
#   - Active VS Code server copy
#   - Hermes agent or its dependencies
#   - Omniroute (running service)
#   - Python or Node runtimes in active use

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

FREED=0

log()  { echo -e "${GREEN}[CLEAN]${NC} $*"; }
skip() { echo -e "${YELLOW}[SKIP]${NC} $*"; }
info() { echo -e "${CYAN}[INFO]${NC} $*"; }
err()  { echo -e "${RED}[ERR ]${NC} $*" >&2; }

get_size_mb() {
    local path="$1"
    if [ -e "$path" ]; then
        du -sm "$path" 2>/dev/null | cut -f1
    else
        echo "0"
    fi
}

remove_if_exists() {
    local path="$1"
    local label="${2:-$path}"
    if [ -e "$path" ]; then
        local size
        size=$(get_size_mb "$path")
        sudo rm -rf "$path"
        log "Removed $label (${size}MB)"
        FREED=$((FREED + size))
    else
        skip "$label already gone"
    fi
}

echo ""
echo "============================================"
echo "  Codespace Disk Cleanup"
echo "============================================"
echo ""

# Show disk before
info "Disk before cleanup:"
df -h / 2>/dev/null | head -2
if mountpoint -q /vscode 2>/dev/null; then
    df -h /vscode 2>/dev/null | tail -1
fi
echo ""

# ─────────────────────────────────────────────
# 1. Ollama GPU libraries (CPU fallback works)
# ─────────────────────────────────────────────
info "Phase 1: Ollama GPU libraries"
if [ -d /usr/local/lib/ollama ]; then
    for gpu_dir in cuda_v12 cuda_v13 vulkan; do
        remove_if_exists "/usr/local/lib/ollama/$gpu_dir" "Ollama $gpu_dir"
    done
else
    skip "Ollama lib directory not found"
fi

# ─────────────────────────────────────────────
# 2. Package manager caches
# ─────────────────────────────────────────────
info "Phase 2: Package manager caches"
if command -v pip &>/dev/null; then
    pip_cache_before=$(du -sm ~/.cache/pip 2>/dev/null | cut -f1 || echo 0)
    pip cache purge 2>/dev/null || true
    log "pip cache purged (~${pip_cache_before}MB)"
    FREED=$((FREED + pip_cache_before))
fi

if command -v npm &>/dev/null; then
    npm_before=$(du -sm ~/.npm 2>/dev/null | cut -f1 || echo 0)
    npm cache clean --force 2>/dev/null || true
    log "npm cache cleared (~${npm_before}MB)"
    FREED=$((FREED + npm_before))
fi

if command -v uv &>/dev/null; then
    uv_before=$(du -sm ~/.cache/uv 2>/dev/null | cut -f1 || echo 0)
    uv cache clean 2>/dev/null || true
    log "uv cache cleared (~${uv_before}MB)"
    FREED=$((FREED + uv_before))
fi

remove_if_exists "$HOME/.cache/electron" "Electron cache"
remove_if_exists "$HOME/.cache/node-gyp" "node-gyp cache"

# ─────────────────────────────────────────────
# 3. Unused language runtimes
# ─────────────────────────────────────────────
info "Phase 3: Unused language runtimes"
remove_if_exists /usr/local/php "PHP"
remove_if_exists /usr/local/rvm "Ruby (rvm)"
remove_if_exists /usr/local/sdkman "SDKMAN (Java/Gradle/Maven)"

# ─────────────────────────────────────────────
# 4. Stale VS Code server copies (biggest win)
# ─────────────────────────────────────────────
info "Phase 4: Stale VS Code server binaries"
find_active_vscode_server() {
    # Find the VS Code server process and extract its hash
    local pid_hash
    pid_hash=$(ps aux 2>/dev/null | grep -oP 'linux-x64/\K[a-f0-9]+(?=/node)' | head -1)
    if [ -n "$pid_hash" ]; then
        echo "$pid_hash"
    else
        # Fallback: find the newest (non-insider) directory
        ls -td /vscode/bin/linux-x64/[0-9a-f]* 2>/dev/null | head -1 | xargs basename 2>/dev/null
    fi
}

ACTIVE_HASH=$(find_active_vscode_server)
if [ -n "$ACTIVE_HASH" ]; then
    info "Active VS Code server: $ACTIVE_HASH"

    for vscode_bin_dir in /vscode/bin/linux-x64 /.codespaces/bin/cache/bin/linux-x64; do
        if [ -d "$vscode_bin_dir" ]; then
            count=0
            for dir in "$vscode_bin_dir"/*/; do
                dirname=$(basename "$dir")
                if [ "$dirname" != "$ACTIVE_HASH" ] && [ -d "$dir" ]; then
                    size=$(get_size_mb "$dir")
                    sudo rm -rf "$dir"
                    FREED=$((FREED + size))
                    count=$((count + 1))
                fi
            done
            if [ $count -gt 0 ]; then
                log "Removed $count stale server copies from $vscode_bin_dir"
            fi
        fi
    done
else
    skip "Could not determine active VS Code server"
fi

# ─────────────────────────────────────────────
# 5. Stale VS Code serverCache
# ─────────────────────────────────────────────
info "Phase 5: Stale VS Code serverCache"
for cache_dir in /vscode/serverCache /.codespaces/bin/cache/serverCache; do
    if [ -d "$cache_dir" ] && [ -n "$ACTIVE_HASH" ]; then
        count=0
        for dir in "$cache_dir"/*/; do
            dirname=$(basename "$dir")
            if [ "$dirname" != "$ACTIVE_HASH" ] && [ -d "$dir" ]; then
                size=$(get_size_mb "$dir")
                sudo rm -rf "$dir"
                FREED=$((FREED + size))
                count=$((count + 1))
            fi
        done
        if [ $count -gt 0 ]; then
            log "Removed $count stale serverCache entries from $cache_dir"
        fi
    fi
done

# ─────────────────────────────────────────────
# 6. Unused global npm packages
# ─────────────────────────────────────────────
info "Phase 6: Unused global npm packages"
if npm ls -g cline 2>/dev/null | grep -q cline; then
    cline_before=$(get_size_mb "$(npm root -g)/cline")
    npm uninstall -g cline 2>/dev/null || true
    log "Removed cline (~${cline_before}MB)"
    FREED=$((FREED + cline_before))
fi

# ─────────────────────────────────────────────
# 7. NVM cleanup (old versions + cache)
# ─────────────────────────────────────────────
info "Phase 7: NVM cleanup"

# SAFETY: Detect active Node version via multiple fallback methods.
# If we can't determine the active version, SKIP this phase entirely
# to avoid removing the only installed Node runtime.
ACTIVE_NODE=""

# Method 1: `node --version` in current PATH
if [ -z "$ACTIVE_NODE" ]; then
    ACTIVE_NODE=$(node --version 2>/dev/null | sed 's/v//')
fi

# Method 2: Check /etc/profile.d for nvm node path
if [ -z "$ACTIVE_NODE" ]; then
    ACTIVE_NODE=$(grep -oP 'nvm/current/bin' /etc/profile.d/00-restore-env.sh 2>/dev/null | head -1 | \
        sed 's|.*nvm/current/bin||' | \
        grep -oP 'nvm/versions/node/v\K[0-9.]+' 2>/dev/null | head -1)
fi

# Method 3: Check the nvm "current" symlink target
if [ -z "$ACTIVE_NODE" ]; then
    for nvm_link in "$HOME/nvm/current" /usr/local/share/nvm/current; do
        if [ -L "$nvm_link" ]; then
            target=$(readlink "$nvm_link" 2>/dev/null)
            ACTIVE_NODE=$(echo "$target" | grep -oP 'v\K[0-9.]+' | head -1)
            if [ -n "$ACTIVE_NODE" ]; then break; fi
        fi
    done
fi

# Method 4: Find the newest node version directory
if [ -z "$ACTIVE_NODE" ]; then
    for nvm_dir in "$HOME/.nvm/versions/node" /usr/local/share/nvm/versions/node; do
        if [ -d "$nvm_dir" ]; then
            ACTIVE_NODE=$(ls -d "$nvm_dir"/v* 2>/dev/null | sort -V | tail -1 | xargs basename 2>/dev/null | sed 's/v//')
            if [ -n "$ACTIVE_NODE" ]; then break; fi
        fi
    done
fi

if [ -z "$ACTIVE_NODE" ]; then
    skip "Could not determine active Node version — skipping NVM cleanup"
else
    info "Active Node version: v$ACTIVE_NODE"

    for nvm_dir in "$HOME/.nvm/versions/node" /usr/local/share/nvm/versions/node; do
        if [ -d "$nvm_dir" ]; then
            version_count=$(ls -d "$nvm_dir"/v* 2>/dev/null | wc -l)
            if [ "$version_count" -le 1 ]; then
                skip "Only one Node version installed (v$ACTIVE_NODE) — keeping it"
                break
            fi
            for ver_dir in "$nvm_dir"/*/; do
                ver=$(basename "$ver_dir" | sed 's/v//')
                if [ "$ver" != "$ACTIVE_NODE" ] && [ -d "$ver_dir" ]; then
                    size=$(get_size_mb "$ver_dir")
                    sudo rm -rf "$ver_dir"
                    log "Removed Node v$ver (~${size}MB)"
                    FREED=$((FREED + size))
                fi
            done
        fi
    done
fi

# Clean nvm cache
for nvm_cache in "$HOME/.nvm/cache" /usr/local/share/nvm/.cache; do
    remove_if_exists "$nvm_cache" "NVM cache"
done

# ─────────────────────────────────────────────
# 8. Unused tools
# ─────────────────────────────────────────────
info "Phase 8: Unused tools"
remove_if_exists /usr/local/hugo "Hugo"
remove_if_exists /usr/local/buildscriptgen "buildscriptgen"
remove_if_exists /usr/local/go "Go"
remove_if_exists /usr/local/bin/minikube "Minikube"
remove_if_exists /usr/local/bin/helm "Helm"
remove_if_exists /usr/local/bin/kubectl "kubectl"
# remove_if_exists /usr/local/bin/docker-compose "Docker Compose"
remove_if_exists /usr/local/bin/copilot "Copilot CLI"

# Remove empty dirs left behind
rmdir /usr/local/share/nvm/versions/node 2>/dev/null || true

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
echo ""
echo "============================================"
echo -e "  ${GREEN}Cleanup complete!${NC}"
echo "============================================"
echo ""
echo "  Space freed: ~${FREED}MB (~$((FREED / 1024)).$((FREED % 1024 * 10 / 1024))GB)"
echo ""
echo "  Disk after cleanup:"
df -h / 2>/dev/null | head -2
if mountpoint -q /vscode 2>/dev/null; then
    df -h /vscode 2>/dev/null | tail -1
fi
echo ""
echo "  Ollama status:"
curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && \
    echo "  ✓ Ollama running, models available" || \
    echo "  ⚠ Ollama not responding (may need restart: ollama serve &)"
echo ""