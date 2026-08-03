#!/bin/bash
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_NAME="$(basename -- "$SCRIPT_PATH")"

# Derive workspace root from script location (works in both Codespace and CI)
# In Codespace: $WORKSPACE is set by devcontainer.json
# In CI: derive from SCRIPT_DIR (which is .devcontainer/)
WORKSPACE_ROOT="${WORKSPACE:-$(dirname "$SCRIPT_DIR")}"

# ── Validate ALL critical dependencies ──────────────────────────────
# Every service binary, the skills directory, and the Mnemon seed file
# MUST exist. If any is missing, the system is incomplete — fail
# immediately with a clear error message before starting any services.
MISSING=()

# Check service binaries
for bin in modelrelay omniroute ollama hermes mnemon; do
  if ! command -v "$bin" &>/dev/null; then
    MISSING+=("binary: $bin")
  fi
done

# Check Persistent Knowledge System
if [ ! -d "$WORKSPACE_ROOT/.devcontainer/skills" ]; then
  MISSING+=("directory: .devcontainer/skills/")
fi
if [ ! -f "$WORKSPACE_ROOT/.devcontainer/mnemon/seed.json" ]; then
  MISSING+=("file: .devcontainer/mnemon/seed.json")
fi

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "[$SCRIPT_NAME] FATAL: Missing critical dependencies:"
  for item in "${MISSING[@]}"; do
    echo "  - $item"
  done
  echo "[$SCRIPT_NAME] All dependencies are required for Hermes to function."
  exit 1
fi

echo
echo "*****   Starting Hermes Agent Services ....    *****"
echo
echo "    $(date)"

# 1. Starting modelrelay...
if pgrep -f modelrelay > /dev/null; then
  echo "[$SCRIPT_NAME] modelrelay is already running, skipping"
else
  echo "[$SCRIPT_NAME] Starting modelrelay in the background..."
  setsid /usr/local/bin/modelrelay >> /tmp/modelrelay.log 2>&1 &
fi

# 2. Starting omniroute...
if pgrep -f omniroute > /dev/null; then
  echo "[$SCRIPT_NAME] omniroute is already running, skipping"
else
  echo "[$SCRIPT_NAME] Starting omniroute in the background..."
  setsid /usr/local/bin/omniroute --no-open --log >> /tmp/omniroute.log 2>&1 &
fi

# 3. Starting ollama...
if pgrep -f ollama > /dev/null; then
  echo "[$SCRIPT_NAME] ollama is already running, skipping"
  ( sleep 60 && ollama pull nomic-embed-text >> /tmp/ollama-pull.log 2>&1 ) &
else
  echo "[$SCRIPT_NAME] Starting ollama in the background..."
  setsid /usr/local/bin/ollama serve >> /tmp/ollama.log 2>&1 &
  ( sleep 60 && ollama pull nomic-embed-text >> /tmp/ollama-pull.log 2>&1 ) &
fi

# 4. Starting Hermes Gateway and Dashboard

# Install Telegram gateway dependency if missing
$HOME/.hermes/hermes-agent/venv/bin/python -m ensurepip --upgrade || true
ln -s $HOME/.hermes/hermes-agent/venv/bin/pip3 $HOME/.hermes/hermes-agent/venv/bin/pip || true
$HOME/.hermes/hermes-agent/venv/bin/pip install python-telegram-bot 2>/dev/null || true

# Update mnemon provider if version changes (synced BEFORE gateway starts)
echo "[$SCRIPT_NAME] Checking mnemon provider..."
rm -rf /tmp/mnemon_repo
if git clone https://github.com/gitricko/hermes-plugin-mnemon /tmp/mnemon_repo; then
    if [ ! -d "$HOME/.hermes/plugins/mnemon" ] || ! diff -r -q -x __pycache__ "$HOME/.hermes/plugins/mnemon" "/tmp/mnemon_repo/mnemon" >/dev/null 2>&1; then
      echo "[$SCRIPT_NAME] Mnemon plugin is missing or out of date. Updating..."
      mkdir -p "$HOME/.hermes/plugins"
      rm -rf "$HOME/.hermes/plugins/mnemon"
      cp -r "/tmp/mnemon_repo/mnemon" "$HOME/.hermes/plugins/mnemon"
      echo "[$SCRIPT_NAME] Mnemon plugin updated successfully."
    else
      echo "[$SCRIPT_NAME] Mnemon plugin is up to date."
    fi
    rm -rf /tmp/mnemon_repo
else
  echo "[$SCRIPT_NAME] WARNING: Failed to clone gitricko/hermes-plugin-mnemon repository."
fi

# Start Hermes Gateway in background (mnemon is ready before this fires)
if pgrep -f 'hermes gateway' > /dev/null; then
  echo "[$SCRIPT_NAME] hermes-gateway is already running, skipping"
else
  echo "[$SCRIPT_NAME] Starting hermes-gateway in the background..."
  setsid hermes gateway run --no-supervise > ~/.hermes/logs/gateway.log 2>&1 &
fi

# Start Hermes Dashboard
if pgrep -f 'hermes dashboard' > /dev/null; then
  echo "[$SCRIPT_NAME] hermes-dashboard is already running, skipping"
else
  echo "[$SCRIPT_NAME] Starting hermes-dashboard in the background..."
  setsid hermes dashboard --port 9119 --no-open > ~/.hermes/logs/dashboard.log 2>&1 &
fi

# Wait for Hermes dashboard to be ready (replaces brittle sleep 15)
echo "[$SCRIPT_NAME] Waiting for Hermes dashboard to become healthy..."
for i in $(seq 1 20); do
  if curl -s -o /dev/null -w "%{http_code}" http://localhost:9119 2>/dev/null | grep -q "200\|302\|401"; then
    echo "[$SCRIPT_NAME] Dashboard ready after $((i * 3)) seconds."
    break
  fi
  if [ "$i" -eq 20 ]; then
    echo "[$SCRIPT_NAME] WARNING: Dashboard did not respond within 60 seconds. Check ~/.hermes/logs/dashboard.log"
  fi
  sleep 3
done

# 5. Create symlink for codebase-specific skills
SKILLS_SYMLINK="$HOME/.hermes/skills/codespace"
SKILLS_TARGET="$WORKSPACE_ROOT/.devcontainer/skills"

if [ ! -L "$SKILLS_SYMLINK" ]; then
    mkdir -p "$HOME/.hermes/skills"
    ln -s "$SKILLS_TARGET" "$SKILLS_SYMLINK"
    echo "[$SCRIPT_NAME] Created skills symlink: $SKILLS_SYMLINK -> $SKILLS_TARGET"
else
    echo "[$SCRIPT_NAME] Skills symlink already exists"
fi

# 5.5.5 Memories folder symlink — REPAIR GUARD ONLY.
# post-create-cmd.sh is the authoritative creator (runs once on a fresh container,
# before Hermes instantiates ~/.hermes/memories). This guard is a cheap safety net
# for pre-existing containers created before that shipped, where the dir may still
# be a real folder. MEMORY.md/USER.md are assumed committed in .devcontainer/memories/
# (their ephemeral .lock/.log siblings are gitignored there).
MEMORIES_RUNTIME="$HOME/.hermes/memories"
MEMORIES_TRACKED="$WORKSPACE_ROOT/.devcontainer/memories"

if [ "$(readlink "$MEMORIES_RUNTIME" 2>/dev/null)" != "$MEMORIES_TRACKED" ]; then
  mkdir -p "$MEMORIES_TRACKED"
  rm -rf "$MEMORIES_RUNTIME"
  ln -s "$MEMORIES_TRACKED" "$MEMORIES_RUNTIME"
  echo "[$SCRIPT_NAME] Repaired memories symlink: $MEMORIES_RUNTIME -> $MEMORIES_TRACKED"
else
  echo "[$SCRIPT_NAME] Memories folder symlink already correct"
fi

# 5.6. Starting keepalive (idempotent) — keeps codespace from idle-shutting-down
if ! pgrep -f "keepalive.sh" > /dev/null; then
    echo "[$SCRIPT_NAME] Starting keepalive..."
    setsid nohup "${SCRIPT_DIR}/keepalive.sh" >> /tmp/keepalive.log 2>&1 &
else
    echo "[$SCRIPT_NAME] keepalive already running"
fi

# 7. Import Mnemon seed data (wiki summaries, key decisions, architecture facts)
SEED_FILE="$WORKSPACE_ROOT/.devcontainer/mnemon/seed.json"
echo "[$SCRIPT_NAME] Importing Mnemon seed data..."
if mnemon import --dry-run "$SEED_FILE" 2>&1 | grep -q "validation passed"; then
  IMPORT_RESULT=$(mnemon import "$SEED_FILE" 2>&1)
  ADDED=$(echo "$IMPORT_RESULT" | grep -o '"imported": *[0-9]*' | grep -o '[0-9]*')
  SKIPPED=$(echo "$IMPORT_RESULT" | grep -o '"skipped": *[0-9]*' | grep -o '[0-9]*')
  ERRORS=$(echo "$IMPORT_RESULT" | grep -o '"errors": *[0-9]*' | grep -o '[0-9]*')
  echo "[$SCRIPT_NAME] Mnemon seed imported: ${ADDED:-0} added, ${SKIPPED:-0} skipped, ${ERRORS:-0} errors"
else
  echo "[$SCRIPT_NAME] WARNING: Mnemon seed validation failed — skipping import"
fi

# All services started and ready
echo "[$SCRIPT_NAME] All hermes-agent services started and ready."

# Run boot-time health self-check after all services are ready
echo "[$SCRIPT_NAME] Running boot-time health self-check..."
${SCRIPT_DIR}/self-check.sh || echo "[$SCRIPT_NAME] WARNING: self-check reported issues"
