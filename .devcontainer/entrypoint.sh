#!/bin/bash
# ── Entrypoint: copies baked configs to $HOME and starts services ─────
# This replaces both post-create-cmd.sh and start-hermes.sh.
# Heavy installs are already in the image; this only does runtime setup.
set -e

SCRIPT_NAME="entrypoint.sh"
echo "*****   Hermes Codespace — Baked Image Entrypoint   *****"

# ── Locate hermes venv (FHS root layout vs legacy) ───────────────────
HERMES_VENV="/usr/local/lib/hermes-agent/venv"
if [ ! -d "$HERMES_VENV" ]; then
    HERMES_VENV="$HOME/.hermes/hermes-agent/venv"
fi
HERMES_PYTHON="$HERMES_VENV/bin/python"
HERMES_PIP="$HERMES_VENV/bin/pip"

# ── Place config files into $HOME (only if not already customized) ───
place_config() {
    local src="$1" dst="$2"
    if [ ! -f "$dst" ] || ! cmp -s "$src" "$dst" 2>/dev/null; then
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        echo "[$SCRIPT_NAME] Placed $(basename "$dst")"
    fi
}

place_config /usr/local/share/devcontainer-config/CLAUDE.md               "$HOME/.claude/CLAUDE.md"
place_config /usr/local/share/devcontainer-config/claude-term-settings.json "$HOME/.claude/settings.json"
place_config /usr/local/share/devcontainer-config/.claude.json             "$HOME/.claude.json"
place_config /usr/local/share/devcontainer-config/.hermes.md               "$HOME/.hermes.md"
place_config /usr/local/share/devcontainer-config/cline-globalState.json   "$HOME/.cline/data/globalState.json"
place_config /usr/local/share/devcontainer-config/cline-secrets.json       "$HOME/.cline/data/secrets.json"
mkdir -p "$HOME/.hermes/skills/memory-automation"
place_config /usr/local/share/devcontainer-config/skill-memory-automation.md "$HOME/.hermes/skills/memory-automation/SKILL.md"

# ── Hermes config defaults (first session only) ──────────────────────
if command -v hermes &>/dev/null \
   && [ ! -f "$HOME/.hermes/config.yaml" ]; then
    echo "[$SCRIPT_NAME] Setting up default Hermes config..."
    hermes config set model.default auto-fastest
    hermes config set model.provider omniroute
    hermes config set providers.omniroute.base_url http://localhost:20128/v1
    hermes config set providers.omniroute.api_key no-key-needed
    hermes config set providers.modelrelay.base_url http://localhost:7352/v1
    hermes config set providers.modelrelay.api_key no-key-needed
    hermes config set fallback_providers.provider modelrelay
    hermes config set fallback_providers.model auto-fastest
    hermes config set auxiliary.title_generation.model auto-fastest
    hermes config set auxiliary.title_generation.provider modelrelay
    hermes config set auxiliary.vision.model auto-fastest
    hermes config set auxiliary.vision.provider modelrelay
    hermes config set auxiliary.compression.model auto-fastest
    hermes config set auxiliary.compression.provider modelrelay
    hermes config set approvals.mode off
    hermes config set memory.memory_enabled true
    hermes config set memory.user_profile_enabled true
    hermes config set memory.provider mnemon
    hermes config set agent.max_turns 120
    hermes config set kanban.failure_limit 3
fi

# ── Mnemon USER.md ───────────────────────────────────────────────────
if [ ! -f "$HOME/.hermes/memories/USER.md" ]; then
    mkdir -p "$HOME/.hermes/memories"
    cat > "$HOME/.hermes/memories/USER.md" <<'USEREOF'
Always use Mnemon (mnemon_remember / mnemon_recall) as primary memory provider instead of the standard memory() tool. Mnemon has no char limit. Only fall back to memory() for structured preference data (target=user or memory).
USEREOF
    echo "[$SCRIPT_NAME] Created USER.md for Mnemon"
fi

# ── Service throttling helpers ───────────────────────────────────────

# Wait for CPU load to drop below threshold before starting next service.
# Prevents multiple CPU-heavy services from launching simultaneously.
wait_for_cpu_ready() {
    local threshold="${1:-60}"       # Max CPU % allowed (default 60%)
    local max_wait="${2:-120}"       # Max seconds to wait (default 120s)
    local poll_interval=3            # Check every 3 seconds

    local elapsed=0
    while [ "$elapsed" -lt "$max_wait" ]; do
        # Read /proc/stat — two snapshots 1 second apart
        local cpu1=$(awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8}' /proc/stat)
        local idle1=$(awk '/^cpu / {print $5}' /proc/stat)
        sleep 1
        local cpu2=$(awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8}' /proc/stat)
        local idle2=$(awk '/^cpu / {print $5}' /proc/stat)

        local total_diff=$((cpu2 - cpu1))
        local idle_diff=$((idle2 - idle1))

        local used_pct=0
        if [ "$total_diff" -gt 0 ]; then
            used_pct=$(( (total_diff - idle_diff) * 100 / total_diff ))
        fi

        if [ "$used_pct" -lt "$threshold" ]; then
            echo "[$SCRIPT_NAME]   CPU ${used_pct}% < ${threshold}% — ready for next service"
            return 0
        fi

        echo "[$SCRIPT_NAME]   CPU ${used_pct}% >= ${threshold}% — waiting... (${elapsed}s/${max_wait}s)"
        sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval + 1))  # +1 for the 1s sleep above
    done

    echo "[$SCRIPT_NAME]   WARNING: CPU still ${used_pct}% after ${max_wait}s — proceeding anyway"
    return 0
}

# Wait for a service port to respond before starting the next service.
wait_for_ready() {
    local port="$1" name="$2" timeout="${3:-60}"
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        if curl -s -o /dev/null -w "" --max-time 2 "http://localhost:${port}" 2>/dev/null; then
            echo "[$SCRIPT_NAME]   ${name} ready on :${port} (${elapsed}s)"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "[$SCRIPT_NAME]   WARNING: ${name} not responding on :${port} after ${timeout}s"
    return 0
}

# ── Start services (only if not already running) ─────────────────────
start_service() {
    local name="$1" cmd="$2"
    local logfile="/tmp/$(echo "$name" | tr ' ' '-').log"
    if pgrep -f "$name" > /dev/null 2>&1; then
        echo "[$SCRIPT_NAME] $name already running, skipping"
    else
        echo "[$SCRIPT_NAME] Starting $name..."
        setsid $cmd >> "$logfile" 2>&1 &
    fi
}

# Set Ollama model path to baked location before starting
export OLLAMA_MODELS=/usr/share/ollama/.ollama/models

# ── Sequential startup with CPU gating + readiness probes ──────────
# Prevents CPU saturation from simultaneous service launches.

echo "[$SCRIPT_NAME] Starting services (throttled)..."
wait_for_cpu_ready 60 90

# 1. Ollama — heaviest (loads nomic-embed-text model)
start_service "ollama serve"     "/usr/local/bin/ollama serve"
echo "[$SCRIPT_NAME]   Waiting for ollama..."
wait_for_cpu_ready 60 90
wait_for_ready 11434 "Ollama" 90

# 2. ModelRelay — moderate (Node.js, starts fast)
start_service "modelrelay"       "/usr/local/bin/modelrelay"
echo "[$SCRIPT_NAME]   Waiting for modelrelay..."
wait_for_cpu_ready 60 90
wait_for_ready 7352 "ModelRelay" 90

# 3. OmniRoute — heavy (Node.js API gateway, SQLite init)
start_service "omniroute"        "/usr/local/bin/omniroute --no-open --log"
echo "[$SCRIPT_NAME]   Waiting for omniroute..."
wait_for_cpu_ready 60 90
wait_for_ready 20128 "OmniRoute" 90

# ── OmniRoute: disable login, create combo ───────────────────────────

# Disable login requirement
if [ -f "$HOME/.omniroute/storage.sqlite" ]; then
    python3 -c "
import sqlite3
conn = sqlite3.connect('$HOME/.omniroute/storage.sqlite')
conn.execute('UPDATE key_value SET value = ? WHERE key = ?', ('false', 'requireLogin'))
conn.commit()
conn.close()
" 2>/dev/null
fi

# Create auto-fastest combo (idempotent)
for ((i=1; i<=5; i++)); do
    omniroute combo create auto-fastest --strategy auto 2>/dev/null && break
    sleep 2
done

# Configure combo models
COMBO_ID=$(omniroute combo list --json 2>/dev/null | grep -v "📋" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print([c['id'] for c in d['combos'] if c['name']=='auto-fastest'][0])" 2>/dev/null)
if [ -n "$COMBO_ID" ]; then
    curl -s -X PUT "http://localhost:20128/api/combos/$COMBO_ID" \
        -H "Content-Type: application/json" \
        -d '{
            "models": ["oc/deepseek-v4-flash-free","oc/big-pickle","opencode-zen/deepseek-v4-flash-free","opencode-zen/hy3-free","opencode-zen/mimo-v2.5-free","opencode-zen/north-mini-code-free","opencode-zen/nemotron-3-ultra-free","opencode-zen/big-pickle"],
            "strategy": "auto",
            "config": {"maxRetries": 2, "retryDelayMs": 1000, "timeoutMs": 120000, "healthCheckEnabled": true}
        }' >/dev/null
fi

# Enable MCP
if ! omniroute mcp status --json 2>/dev/null | python3 -c "import sys,json;exit(0 if json.load(sys.stdin).get('enabled') else 1)" 2>/dev/null; then
    curl -s -X PATCH http://localhost:20128/api/settings \
        -H "Content-Type: application/json" -d '{"mcpEnabled":true}' >/dev/null
fi

# Add omniroute MCP to hermes
yes Y 2>/dev/null | hermes mcp add omniroute --command omniroute --args --mcp 2>/dev/null || true

# ── Hermes gateway + dashboard ────────────────────────────────────────
# Update mnemon plugin
rm -rf /tmp/mnemon_repo
if git clone https://github.com/gitricko/hermes-plugin-mnemon /tmp/mnemon_repo 2>/dev/null; then
    if [ ! -d "$HOME/.hermes/plugins/mnemon" ] || ! diff -r -q -x __pycache__ "$HOME/.hermes/plugins/mnemon" "/tmp/mnemon_repo/mnemon" >/dev/null 2>&1; then
        mkdir -p "$HOME/.hermes/plugins"
        rm -rf "$HOME/.hermes/plugins/mnemon"
        cp -r "/tmp/mnemon_repo/mnemon" "$HOME/.hermes/plugins/mnemon"
    fi
    rm -rf /tmp/mnemon_repo
fi

start_service "hermes gateway"   "hermes gateway run --no-supervise"
echo "[$SCRIPT_NAME]   Waiting for hermes gateway..."
wait_for_cpu_ready 60 90

start_service "hermes dashboard" "hermes dashboard --port 9119 --no-open --skip-build"
echo "[$SCRIPT_NAME]   Waiting for hermes dashboard..."
wait_for_ready 9119 "Hermes Dashboard" 90

# Telegram bot deps (use hermes venv Python if available)
if [ -x "$HERMES_PYTHON" ]; then
    "$HERMES_PYTHON" -m ensurepip --upgrade 2>/dev/null || true
    ln -sf "$HERMES_PIP" "$HERMES_VENV/bin/pip" 2>/dev/null || true
    "$HERMES_PIP" install python-telegram-bot 2>/dev/null || true
fi

# Mnemon -> claude-code integration
mnemon setup --yes --global --target claude-code 2>/dev/null || true

echo "[$SCRIPT_NAME] All services started."
echo "[$SCRIPT_NAME] Running self-check..."
/usr/local/bin/self-check.sh 2>/dev/null || echo "[$SCRIPT_NAME] WARNING: self-check reported issues"

# ── Execute the CMD (default: sleep infinity) ─────────────────────────
exec "$@"
