#!/bin/bash

HERMES_VERSION="v2026.8.31"
OMNIROUTE_VERSION=3.8.49
MODELRELAY_VERSION=1.22.1
OLLAMA_VERSION=0.33.2
NODE_VERSION=26.7.0
MNEMON_VERSION=0.2.7
PI_AGENT_VERSION=0.84.4
HERDR_VERSION=0.7.4

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_NAME="$(basename -- "$SCRIPT_PATH")"

# Smart copy: only copies if files differ or destination doesn't exist
smart_copy() {
  if ! cmp -s "$1" "$2" 2>/dev/null; then
    cp "$1" "$2"
    echo "✓ Updated $(basename "$2")"
  else
    echo "✓ $(basename "$2") already in sync"
  fi
}

echo
echo "*****   Installing/Setup Hermes Agent Services ....    *****"
echo 

sudo apt-get update && sudo apt-get install -y zsh ripgrep && sudo rm -rf /var/lib/apt/lists/*

# Install the Ollama binary from the official image
curl -fsSL https://ollama.com/install.sh | sh

echo "[$SCRIPT_NAME] Checking ollama..."
if command -v ollama &>/dev/null; then
  if pgrep -f ollama > /dev/null; then
    echo "[$SCRIPT_NAME] ollama is already running, skipping"
    ( sleep 60 && ollama pull nomic-embed-text >> /tmp/ollama-pull.log 2>&1 ) &
  else
    echo "[$SCRIPT_NAME] Starting ollama in the background..."
    setsid /usr/local/bin/ollama serve >> /tmp/ollama.log 2>&1 &
    ( sleep 60 && ollama pull nomic-embed-text >> /tmp/ollama-pull.log 2>&1 ) &
  fi
else
  echo "[$SCRIPT_NAME] ollama not found, skipping start"
fi

# Install hermes-agent (fix 429 from github issue)
HERMES_INSTALL_URI="https://raw.githubusercontent.com/NousResearch/hermes-agent/${HERMES_VERSION}/scripts/install.sh"
HERMES_FALLBACK_URI="https://hermes-agent.nousresearch.com/install.sh"
INSTALL_SCRIPT="$(mktemp)"

if ! curl -fsSL --max-time 15 --retry 3 -o "$INSTALL_SCRIPT" "$HERMES_INSTALL_URI"; then
  echo "[$SCRIPT_NAME] Primary Hermes installer failed; trying fallback..."
  if ! curl -fsSL --max-time 15 --retry 3 -o "$INSTALL_SCRIPT" "$HERMES_FALLBACK_URI"; then
    echo "[$SCRIPT_NAME] Could not download Hermes installer."
    rm -f "$INSTALL_SCRIPT"
    exit 1
  fi
fi

if ! bash "$INSTALL_SCRIPT" --skip-setup; then
  echo "[$SCRIPT_NAME] Hermes installer failed."
  rm -f "$INSTALL_SCRIPT"
  exit 1
fi
rm -f "$INSTALL_SCRIPT"
npm cache clean --force
sudo rm -rf /var/lib/apt/lists/* 

# Symlink the Hermes memories dir into the repo (skills-style folder symlink).
# postCreateCommand runs exactly once on a FRESH container, so this is the
# authoritative, cleanest place to set it up — before Hermes first instantiates
# ~/.hermes/memories. MEMORY.md/USER.md are guaranteed present in git at this
# point, so we never need to migrate/seed content here. Ephemeral .lock/.log files
# Hermes writes inside are gitignored (see .devcontainer/memories/.gitignore).
HERMES_MEMORIES="$HOME/.hermes/memories"
TRACKED_MEMORIES="${SCRIPT_DIR}/memories"
mkdir -p "$TRACKED_MEMORIES"
if [ "$(readlink "$HERMES_MEMORIES" 2>/dev/null)" != "$TRACKED_MEMORIES" ]; then
  rm -rf "$HERMES_MEMORIES"
  ln -s "$TRACKED_MEMORIES" "$HERMES_MEMORIES"
  echo "[$SCRIPT_NAME] Created memories folder symlink: $HERMES_MEMORIES -> $TRACKED_MEMORIES"
else
  echo "[$SCRIPT_NAME] Memories folder symlink already correct"
fi

# Ensure agent-client-protocol (ACP) is installed
echo "[$SCRIPT_NAME] Checking agent-client-protocol (ACP)..."
if command -v hermes &>/dev/null; then
  HERMES_VENV_PYTHON="$HOME/.hermes/hermes-agent/venv/bin/python"
  if [ -x "$HERMES_VENV_PYTHON" ]; then
    if ! "$HERMES_VENV_PYTHON" -c "import agent_client_protocol" 2>/dev/null; then
      echo "[$SCRIPT_NAME] ACP not found, installing..."
      "$HERMES_VENV_PYTHON" -m pip install "agent-client-protocol>=0.9.0,<1.0"
    else
      echo "[$SCRIPT_NAME] ACP already installed"
    fi
  fi
else
  echo "[$SCRIPT_NAME] hermes not found, skipping ACP check"
fi

# Configure hermes defaults if first run
if command -v hermes &>/dev/null && [ -d "$HOME/.hermes/sessions" ] && [ -z "$(ls -A "$HOME/.hermes/sessions")" ]; then
  echo "[$SCRIPT_NAME] No sessions found, setting up default configuration for custom provider"
  echo "[$SCRIPT_NAME] Initializing hermes config..."

  hermes config set terminal.cwd $HOME
  hermes config set display.busy_input_mode steer
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

  # Turn off approval alert and live dangerously since u are in a self-contained container.
  hermes config set approvals.mode off
  # Turn on memory by default and to mnemon
  hermes config set memory.memory_enabled true
  hermes config set memory.user_profile_enabled true
  hermes config set memory.provider mnemon
  # optimize for kanban
  hermes config set agent.max_turns 120
  hermes config set kanban.failure_limit 3

  # Populate default skill and .hermes.md
  echo "[$SCRIPT_NAME] Installing Skill: memory-automation.md"
  mkdir -p "$HOME/.hermes/skills/memory-automation"
  cp ${SCRIPT_DIR}/skill-memory-automation.md "$HOME/.hermes/skills/memory-automation/SKILL.md"

  echo "[$SCRIPT_NAME] Populate .hermes.md"
  cp ${SCRIPT_DIR}/.hermes.md "$HOME/.hermes.md"

fi

# Install modelrelay globally
# sudo npm install -g modelrelay@${MODELRELAY_VERSION} && \
sudo npm install github:gitricko/modelrelay -g --prefix /usr/local/lib/modelrelay
sudo ln -sf /usr/local/lib/modelrelay/bin/modelrelay /usr/local/bin/modelrelay
sudo npm cache clean --force

echo "[$SCRIPT_NAME] Checking modelrelay..."
if command -v modelrelay &>/dev/null; then
  if pgrep -f modelrelay > /dev/null; then
    echo "[$SCRIPT_NAME] modelrelay is already running, skipping"
  else
    echo "[$SCRIPT_NAME] Starting modelrelay in the background..."
    modelrelay --disable
    setsid /usr/local/bin/modelrelay >> /tmp/modelrelay.log 2>&1 &
  fi
else
  echo "[$SCRIPT_NAME] modelrelay not found, skipping start"
fi

# Install OmniRoute and start automatically when desktop loads
sudo npm install omniroute@${OMNIROUTE_VERSION} -g --prefix /usr/local/lib/omniroute
sudo ln -sf /usr/local/lib/omniroute/bin/omniroute /usr/local/bin/omniroute

# ── WORKAROUND: repair hollow bundled deps in omniroute's dist/node_modules ──
# The published omniroute npm tarball (observed on 3.8.48) ships an incomplete
# dist/node_modules/: several bundled dependency dirs contain ONLY a package.json
# stub with no JS/native code. This crashes the MCP server on startup with e.g.
#   Error: Cannot find package '.../dist/node_modules/undici/index.js'
# and Hermes then saves the MCP server as disabled ("Failed to connect").
# npm's own resolution fills the SIBLING node_modules/ correctly, so we copy the
# full package over each hollow stub. Auto-detects the broken set so it keeps
# working across OMNIROUTE_VERSION bumps. Must run BEFORE `npm cache clean`.
# Upstream bug — remove once the omniroute tarball ships a complete dist/.
repair_omniroute_dist_deps() {
  local omni_root="/usr/local/lib/omniroute/lib/node_modules/omniroute"
  local dist_nm="$omni_root/dist/node_modules"
  local parent_nm="$omni_root/node_modules"

  [ -d "$dist_nm" ] || { echo "[$SCRIPT_NAME] omniroute dist/node_modules not found, skipping dep repair"; return 0; }

  echo "[$SCRIPT_NAME] Scanning omniroute dist/node_modules for hollow bundled deps..."
  local repaired=0

  # Enumerate candidate package dirs, including scoped (@scope/name) packages.
  local pkg_dirs=()
  while IFS= read -r d; do pkg_dirs+=("$d"); done < <(
    find "$dist_nm" -mindepth 1 -maxdepth 1 -type d 2>/dev/null
  )
  local scope
  for scope in "$dist_nm"/@*/; do
    [ -d "$scope" ] || continue
    while IFS= read -r d; do pkg_dirs+=("$d"); done < <(
      find "$scope" -mindepth 1 -maxdepth 1 -type d 2>/dev/null
    )
  done

  local dst
  for dst in "${pkg_dirs[@]}"; do
    # A scope dir (@foo) itself is not a package; skip it (its children are handled).
    case "$(basename "$dst")" in @*) [ -f "$dst/package.json" ] || continue ;; esac

    # "Hollow" = no executable/native code shipped in this package dir.
    local code_files
    code_files=$(find "$dst" \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.node' -o -name '*.so' \) -type f 2>/dev/null | head -1)
    [ -n "$code_files" ] && continue

    # Map to the sibling node_modules path (preserves @scope/name).
    local rel="${dst#"$dist_nm"/}"
    local src="$parent_nm/$rel"
    [ -d "$src" ] || { echo "[$SCRIPT_NAME]   ! $rel is hollow but no sibling copy — leaving as-is"; continue; }

    local src_code
    src_code=$(find "$src" \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.node' -o -name '*.so' \) -type f 2>/dev/null | head -1)
    [ -n "$src_code" ] || { echo "[$SCRIPT_NAME]   ! sibling $rel also has no code — leaving as-is"; continue; }

    sudo rm -rf "$dst"
    sudo mkdir -p "$(dirname "$dst")"
    sudo cp -r "$src" "$dst"
    echo "[$SCRIPT_NAME]   ✓ Repaired hollow dist dep: $rel"
    repaired=$((repaired + 1))
  done

  echo "[$SCRIPT_NAME] omniroute dep repair complete ($repaired package(s) restored)"
}
repair_omniroute_dist_deps

sudo npm cache clean --force
# sudo mkdir -p /usr/local/lib/node_modules/omniroute/app/logs/application

echo "[$SCRIPT_NAME] Checking omniroute..."
if command -v omniroute &>/dev/null; then
  if pgrep -f omniroute > /dev/null; then
    echo "[$SCRIPT_NAME] omniroute is already running, skipping"
  else
    echo "[$SCRIPT_NAME] Starting omniroute in the background..."
    setsid /usr/local/bin/omniroute --no-open >> /tmp/omniroute.log 2>&1 &
  fi
else
    echo "[$SCRIPT_NAME] omniroute not found, skipping start"
fi


# Install Pi-agent for firstmate-bridge crewmate harness
echo "[$SCRIPT_NAME] Installing Pi-agent..."
if command -v pi &>/dev/null; then
  echo "[$SCRIPT_NAME] pi already installed: $(pi --version 2>&1 | head -1)"
else
  sudo npm install -g --ignore-scripts @earendil-works/pi-coding-agent@${PI_AGENT_VERSION}
  echo "[$SCRIPT_NAME] pi-agent installed"
fi

# Install TailScale
sudo mkdir -p /var/run/tailscale /var/lib/tailscale && sudo curl -fsSL https://tailscale.com/install.sh | sh && sudo rm -rf /var/lib/apt/lists/*

# Install mnemon
MNEMON_ARCH=amd64
curl -sL "https://github.com/mnemon-dev/mnemon/releases/download/v${MNEMON_VERSION}/mnemon_${MNEMON_VERSION}_linux_${MNEMON_ARCH}.tar.gz" -o /tmp/mnemon.tar.gz
tar xzf /tmp/mnemon.tar.gz -C /tmp
sudo cp /tmp/mnemon /usr/local/bin/mnemon
sudo chmod +x /usr/local/bin/mnemon
rm -rf /tmp/mnemon.tar.gz /tmp/mnemon

# Install Herdr (pinned CI-verified build with SHA-256 verification)
# Mirrors docker/scripts/fm-install-herdr.sh logic
HERDR_REPO=ogulcancelik/herdr
HERDR_TAG="v${HERDR_VERSION}"
HERDR_ASSET=herdr-linux-x86_64
HERDR_SHA256=bc0fc02d4ba500f9cac2353a43e67fe036785ecca6eb55378e050fac3c103059
HERDR_MAX_BYTES=25000000

echo "[$SCRIPT_NAME] Installing Herdr ${HERDR_VERSION}..."
HERDR_TMP=$(mktemp -d /tmp/herdr-install.XXXXXX)
trap 'rm -rf "$HERDR_TMP"' EXIT
HERDR_URL="https://github.com/${HERDR_REPO}/releases/download/${HERDR_TAG}/${HERDR_ASSET}"
curl -fsSL --max-filesize "$HERDR_MAX_BYTES" "$HERDR_URL" -o "$HERDR_TMP/$HERDR_ASSET" || {
  echo "[$SCRIPT_NAME] Herdr download failed for $HERDR_URL"
  exit 1
}
ACTUAL_SHA256=$(sha256sum "$HERDR_TMP/$HERDR_ASSET" | awk '{print $1}')
[ "$ACTUAL_SHA256" = "$HERDR_SHA256" ] || {
  echo "[$SCRIPT_NAME] Herdr checksum mismatch (expected $HERDR_SHA256, got $ACTUAL_SHA256)"
  exit 1
}
sudo install -m 0755 "$HERDR_TMP/$HERDR_ASSET" /usr/local/bin/herdr
# Post-install gate: exact version + protocol floor
installed_version=$("/usr/local/bin/herdr" --version 2>/dev/null | awk '{print $2; exit}')
[ "$installed_version" = "$HERDR_VERSION" ] || {
  echo "[$SCRIPT_NAME] installed herdr version is '${installed_version:-<empty>}', expected exact pin $HERDR_VERSION"
  exit 1
}
protocol=$("/usr/local/bin/herdr" status --json 2>/dev/null | jq -r '.client.protocol // empty')
[ -n "$protocol" ] && [ "$protocol" -ge 16 ] || {
  echo "[$SCRIPT_NAME] herdr protocol ${protocol:-<unknown>} is below required floor 16"
  exit 1
}
echo "[$SCRIPT_NAME] Herdr ${HERDR_VERSION} (protocol $protocol) installed to /usr/local/bin/herdr"

# Install Cline with default configuration
echo "[$SCRIPT_NAME] Installing Cline with default configuration..."
mkdir -p "$HOME/.cline/data"
smart_copy "${SCRIPT_DIR}/cline-globalState.json" "$HOME/.cline/data/globalState.json"
smart_copy "${SCRIPT_DIR}/cline-secrets.json" "$HOME/.cline/data/secrets.json"
npm install -g cline

# Install Claude CLI and Extension
mkdir -p $HOME/.claude
cp ${SCRIPT_DIR}/claude-term-settings.json $HOME/.claude/settings.json
curl -fsSL https://claude.ai/install.sh | bash
cp ${SCRIPT_DIR}/.claude.json $HOME/.claude.json
cp ${SCRIPT_DIR}/CLAUDE.md $HOME/.claude/CLAUDE.md
VSCODE_SETTINGS_JSON="$HOME/.vscode-remote/data/Machine/settings.json"
TEMPFILE="$(mktemp)"
jq '
  .claudeCode //= {}
  | .claudeCode.disableLoginPrompt //= true
  | .claudeCode.environmentVariables //= [
      { "name": "ANTHROPIC_BASE_URL", "value": "http://localhost:7352" },
      { "name": "ANTHROPIC_API_KEY", "value": "sk_whatever" },
      { "name": "ANTHROPIC_MODEL", "value": "auto-fastest" }
    ]
' "$VSCODE_SETTINGS_JSON" > "$TEMPFILE" && mv "$TEMPFILE" "$VSCODE_SETTINGS_JSON"

# integrate mnemon into claude-code
mnemon setup --yes --global  --target claude-code


# Preconfigure Omniroute
#   Wait for OmniRoute to be ready
MAX_ATTEMPTS=10
for ((attempt=1; attempt<=MAX_ATTEMPTS; attempt++)); do
    echo "[$SCRIPT_NAME] Waiting for OmniRoute to be ready (attempt $attempt/$MAX_ATTEMPTS)..."
    
    if curl -s --max-time 3 -o /dev/null -w "%{http_code}" http://localhost:20128/v1/models | grep -q "200"; then
        break
    fi
    if [ "$attempt" -eq "$MAX_ATTEMPTS" ]; then
        echo "[$SCRIPT_NAME] Error: OmniRoute failed to start after $MAX_ATTEMPTS attempts."
        exit 1
    fi
    sleep 1
done


# Switch OmniRoute to not require login for now, can enable later
echo "[$SCRIPT_NAME] Switching OmniRoute to not require login..."
python3 -c "
import sqlite3
conn = sqlite3.connect('$HOME/.omniroute/storage.sqlite')
conn.execute('UPDATE key_value SET value = ? WHERE key = ?', ('false', 'requireLogin'))
conn.commit()
conn.close()
"

# Create auto-fastest combo
while ! omniroute combo create auto-fastest --strategy auto ; do
    echo "[$SCRIPT_NAME] omniroute still not ready yet, retrying..."
    sleep 3
done
echo "[$SCRIPT_NAME] OmniRoute Combo auto-fastest created!"

# Enable OmniRoute MCP if not already enabled
if omniroute mcp status --json 2>/dev/null | python3 -c "import sys,json;exit(0 if json.load(sys.stdin).get('enabled') else 1)"; then
    echo "[$SCRIPT_NAME] MCP enabled"
else
    echo "[$SCRIPT_NAME] Enabling MCP..."
    curl -s -X PATCH http://localhost:20128/api/settings \
        -H "Content-Type: application/json" -d '{"mcpEnabled":true}' >/dev/null
    echo "[$SCRIPT_NAME] MCP enabled"
fi

# Add omniroute MCP to hermes
yes Y | hermes mcp add omniroute --command omniroute --args --mcp

# 2. Get the combo ID (skip the banner line from CLI output)
COMBO_ID=$(omniroute combo list --json | grep -v "📋" | \
python3 -c "import sys,json; d=json.load(sys.stdin); print([c['id'] for c in d['combos'] if c['name']=='auto-fastest'][0])")

# 3. Add models + config via API
curl -s -X PUT "http://localhost:20128/api/combos/$COMBO_ID" \
-H "Content-Type: application/json" \
-d '{
    "models": ["oc/deepseek-v4-flash-free","oc/big-pickle","opencode-zen/deepseek-v4-flash-free","opencode-zen/hy3-free","opencode-zen/mimo-v2.5-free","opencode-zen/north-mini-code-free","opencode-zen/nemotron-3-ultra-free","opencode-zen/big-pickle"],
    "strategy": "auto",
    "config": {
    "maxRetries": 2,
    "retryDelayMs": 1000,
    "timeoutMs": 120000,
    "healthCheckEnabled": true
    }
}'

echo "[$SCRIPT_NAME] OmniRoute initialization complete!"

# ── Pre-build Hermes Dashboard web UI ──────────────────────────────────────
# The dashboard auto-builds its web UI (npm ci + vite build) on first boot,
# but npm ci can fail silently in CI environments, leaving port 9119
# unreachable and the smoke test failing with exit code 2. Build it here so
# the dashboard finds a ready dist/ and skips the fragile runtime build.
HERMES_AGENT_DIR="$HOME/.hermes/hermes-agent"
if [ -d "$HERMES_AGENT_DIR/web" ] && command -v node &>/dev/null; then
  echo "[$SCRIPT_NAME] Pre-building Hermes Dashboard web UI..."
  cd "$HERMES_AGENT_DIR"
  CI=1 npm ci --include=dev --workspace web --silent 2>&1 || {
    echo "[$SCRIPT_NAME] npm ci failed, trying npm install fallback..."
    CI=1 npm install --no-save --include=dev --workspace web --silent 2>&1
  }
  cd "$HERMES_AGENT_DIR/web" && CI=1 npm run build 2>&1
  echo "[$SCRIPT_NAME] Hermes Dashboard web UI built successfully."
else
  echo "[$SCRIPT_NAME] Skipping web UI build (no web workspace or node not found)"
fi
