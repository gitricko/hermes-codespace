#!/bin/bash
# ── Entrypoint: copies baked configs to $HOME and starts services ─────
# This replaces both post-create-cmd.sh and start-hermes.sh.
# Heavy installs are already in the image; this only does runtime setup.
set -e

SCRIPT_NAME="entrypoint.sh"
echo "*****   Hermes Codespace — Baked Image Entrypoint   *****"

# ── Place config files into $HOME (only if not already customized) ───
place_config() {
    local src="$1" dst="$2"
    if [ ! -f "$dst" ] || ! cmp -s "$src" "$dst" 2>/dev/null; then
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        echo "[$SCRIPT_NAME] Placed $(basename "$dst")"
    fi
}

place_config /tmp/devcontainer-config/CLAUDE.md               "$HOME/.claude/CLAUDE.md"
place_config /tmp/devcontainer-config/claude-term-settings.json "$HOME/.claude/settings.json"
place_config /tmp/devcontainer-config/.claude.json             "$HOME/.claude.json"
place_config /tmp/devcontainer-config/.hermes.md               "$HOME/.hermes.md"
place_config /tmp/devcontainer-config/cline-globalState.json   "$HOME/.cline/data/globalState.json"
place_config /tmp/devcontainer-config/cline-secrets.json       "$HOME/.cline/data/secrets.json"
mkdir -p "$HOME/.hermes/skills/memory-automation"
place_config /tmp/devcontainer-config/skill-memory-automation.md "$HOME/.hermes/skills/memory-automation/SKILL.md"

# ── Hermes config defaults (first session only) ──────────────────────
if command -v hermes &>/dev/null \
   && [ -d "$HOME/.hermes/sessions" ] && [ -z "$(ls -A "$HOME/.hermes/sessions" 2>/dev/null)" ]; then
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

# ── Start services (only if not already running) ─────────────────────
start_service() {
    local name="$1" cmd="$2"
    if pgrep -f "$name" > /dev/null 2>&1; then
        echo "[$SCRIPT_NAME] $name already running, skipping"
    else
        echo "[$SCRIPT_NAME] Starting $name..."
        setsid $cmd >> /tmp/${name}.log 2>&1 &
    fi
}

start_service "ollama serve"     "/usr/local/bin/ollama serve"
start_service "modelrelay"       "/usr/local/bin/modelrelay"
start_service "omniroute"        "/usr/local/bin/omniroute --no-open --log"

# Pull nomic-embed-text in background after 60s
( sleep 60 && ollama pull nomic-embed-text >> /tmp/ollama-pull.log 2>&1 ) &

# ── OmniRoute: wait for ready, disable login, create combo ────────────
MAX_ATTEMPTS=10
for ((attempt=1; attempt<=MAX_ATTEMPTS; attempt++)); do
    if curl -s --max-time 3 -o /dev/null -w "%{http_code}" http://localhost:20128/v1/models 2>/dev/null | grep -q "200"; then
        break
    fi
    [ "$attempt" -eq "$MAX_ATTEMPTS" ] && echo "[$SCRIPT_NAME] WARNING: OmniRoute not ready"
    sleep 1
done

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
start_service "hermes dashboard" "hermes dashboard --port 9119 --no-open"

# Telegram bot deps
$HOME/.hermes/hermes-agent/venv/bin/python -m ensurepip --upgrade 2>/dev/null || true
ln -sf $HOME/.hermes/hermes-agent/venv/bin/pip3 $HOME/.hermes/hermes-agent/venv/bin/pip 2>/dev/null || true
$HOME/.hermes/hermes-agent/venv/bin/pip install python-telegram-bot 2>/dev/null || true

# Mnemon -> claude-code integration
mnemon setup --yes --global --target claude-code 2>/dev/null || true

echo "[$SCRIPT_NAME] All services started."
echo "[$SCRIPT_NAME] Running self-check..."
/usr/local/bin/self-check.sh 2>/dev/null || echo "[$SCRIPT_NAME] WARNING: self-check reported issues"

# ── Execute the CMD (default: sleep infinity) ─────────────────────────
exec "$@"