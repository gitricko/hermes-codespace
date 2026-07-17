#!/bin/bash
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_NAME="$(basename -- "$SCRIPT_PATH")"

echo "[$SCRIPT_NAME] 1. Starting modelrelay..."
if command -v modelrelay &>/dev/null; then
  if pgrep -f modelrelay > /dev/null; then
    echo "[$SCRIPT_NAME] modelrelay is already running, skipping"
  else
    echo "[$SCRIPT_NAME] Starting modelrelay in the background..."
    setsid /usr/local/bin/modelrelay >> /tmp/modelrelay.log 2>&1 &
  fi
else
  echo "[$SCRIPT_NAME] modelrelay not found, skipping start"
fi

echo "[$SCRIPT_NAME] 2. Starting omniroute..."
if command -v omniroute &>/dev/null; then
  if pgrep -f omniroute > /dev/null; then
    echo "[$SCRIPT_NAME] omniroute is already running, skipping"
  else
    echo "[$SCRIPT_NAME] Starting omniroute in the background..."
    setsid /usr/local/bin/omniroute --no-open  --log >> /tmp/omniroute.log 2>&1 &
  fi
else
  echo "[$SCRIPT_NAME] omniroute not found, skipping start"
fi

echo "[$SCRIPT_NAME] 3. Starting ollama..."
if command -v ollama &>/dev/null; then
  if pgrep -f ollama > /dev/null; then
    echo "[$SCRIPT_NAME] ollama is already running, skipping"
  else
    echo "[$SCRIPT_NAME] Starting ollama in the background..."
    setsid /usr/local/bin/ollama serve >> /tmp/ollama.log 2>&1 &
    ( sleep 60 && ollama pull nomic-embed-text >> /tmp/ollama-pull.log 2>&1 ) &
  fi
else
  echo "[$SCRIPT_NAME] ollama not found, skipping start"
fi


if [ -d "$HOME/.hermes/logs" ] && [ -z "$(ls -A "$HOME/.hermes/logs")" ]; then
  echo "[$SCRIPT_NAME] No logs found in $HOME/.hermes/logs, setting up default configuration for custom provider"
  echo "[$SCRIPT_NAME] Initializing hermes config..."
  hermes config set model.default auto-fastest
  hermes config set model.provider modelrelay
  hermes config set providers.omniroute.base_url http://localhost:20128/v1
  hermes config set providers.omniroute.api_key no-key-needed
  hermes config set providers.modelrelay.base_url http://localhost:7352/v1
  hermes config set providers.modelrelay.api_key no-key-needed
  hermes config set fallback_providers.provider modelrelay
  hermes config set fallback_providers.model auto-fastest

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

mkdir -p  ~/.hermes/logs

# Install Telegram gateway dependency if missing
$HOME/.hermes/hermes-agent/venv/bin/python -m ensurepip --upgrade || true
ln -s $HOME/.hermes/hermes-agent/venv/bin/pip3 $HOME/.hermes/hermes-agent/venv/bin/pip || true
$HOME/.hermes/hermes-agent/venv/bin/pip install python-telegram-bot 2>/dev/null || true

# update mnemon provider if version changes (synced BEFORE gateway starts)
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
echo "[$SCRIPT_NAME] 4. Starting Hermes Gateway..."
if command -v hermes &>/dev/null; then
  if pgrep -f 'hermes gateway' > /dev/null; then
    echo "[$SCRIPT_NAME] hermes-gateway is already running, skipping"
  else
    echo "[$SCRIPT_NAME] Starting hermes-gateway in the background..."
    setsid hermes gateway run --no-supervise > ~/.hermes/logs/gateway.log 2>&1 &
  fi
else
  echo "[$SCRIPT_NAME] hermes not found, skipping start"
fi

  # echo "[$SCRIPT_NAME] Starting Hermes Gateway..."
  # nohup hermes gateway run --no-supervise > ~/.hermes/logs/gateway.log 2>&1 &

  # Start Hermes Dashboard in background
  # echo "[$SCRIPT_NAME] Starting Hermes Dashboard..."
  # nohup hermes dashboard --port 9119 --no-open > ~/.hermes/logs/dashboard.log 2>&1 &

echo "[$SCRIPT_NAME] 5. Starting Hermes Dashboard..."
if command -v hermes &>/dev/null; then
  if pgrep -f 'hermes dashboard' > /dev/null; then
    echo "[$SCRIPT_NAME] hermes-dashboard is already running, skipping"
  else
    echo "[$SCRIPT_NAME] Starting hermes-dashboard in the background..."
    setsid hermes dashboard --port 9119 --no-open > ~/.hermes/logs/dashboard.log 2>&1 &
  fi
else
  echo "[$SCRIPT_NAME] hermes not found, skipping start"
fi

# Remind Hermes on Mnemon setup if needed
if [ ! -f "$HOME/.hermes/memories/USER.md" ]; then
  echo "[$SCRIPT_NAME] Setting up Mnemon USER.md..."
  echo 'Always use Mnemon (mnemon_remember / mnemon_recall) as primary memory provider instead of the standard memory() tool. Mnemon has no char limit. Only fall back to memory() for structured preference data (target=user or memory).' > "$HOME/.hermes/memories/USER.md"
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

# All services started and ready  
echo "[$SCRIPT_NAME] All hermes-agent services started and ready."

# Run boot-time health self-check after all services are ready
echo "[$SCRIPT_NAME] Running boot-time health self-check..."
${SCRIPT_DIR}/self-check.sh || echo "[$SCRIPT_NAME] WARNING: self-check reported issues"
