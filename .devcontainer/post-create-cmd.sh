#!/bin/bash

HERMES_VERSION="v2026.7.7.2"
OMNIROUTE_VERSION=3.8.48
MODELRELAY_VERSION=1.18.0
OLLAMA_VERSION=0.32.0
NODE_VERSION=24.18.0
MNEMON_VERSION=0.1.17

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

sudo apt-get update && sudo apt-get install -y htop zsh ripgrep gh remmina iputils-ping net-tools socat && sudo rm -rf /var/lib/apt/lists/*

# InstallNode.js binaries and libraries

# Install the Ollama binary from the official image
curl -fsSL https://ollama.com/install.sh | sh

echo "[post-create-cmd.sh] Checking ollama..."
if command -v ollama &>/dev/null; then
  if pgrep -f ollama > /dev/null; then
    echo "[post-create-cmd.sh] ollama is already running, skipping"
  else
    echo "[post-create-cmd.sh] Starting ollama in the background..."
    setsid /usr/local/bin/ollama serve >> /tmp/ollama.log 2>&1 &
    ( sleep 60 && ollama pull nomic-embed-text >> /tmp/ollama-pull.log 2>&1 ) &
  fi
else
  echo "[post-create-cmd.sh] ollama not found, skipping start"
fi


# Install ripgrep for better search performance in hermes-agent
# RIPGREP_VERSION=15.1.0
# if ! command -v rg &>/dev/null; then
#   echo "[post-create-cmd.sh] Installing ripgrep for better search performance in hermes-agent..."
#   if [[ "$OSTYPE" == "linux-gnu"* ]]; then
#     # Linux
#     cd /tmp
#     curl -LO https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/ripgrep_${RIPGREP_VERSION}-1_amd64.deb
#     sudo dpkg -i ripgrep_${RIPGREP_VERSION}-1_amd64.deb
#     rm ripgrep_${RIPGREP_VERSION}-1_amd64.deb
#   fi
# fi

# Install hermes-agent
if ! command -v hermes &>/dev/null; then
  echo "[post-create-cmd.sh] Installing hermes-agent ${HERMES_VERSION}..."
  curl -fsSL "https://raw.githubusercontent.com/NousResearch/hermes-agent/${HERMES_VERSION}/scripts/install.sh" | bash -s -- --skip-setup
  npm cache clean --force
  sudo rm -rf /var/lib/apt/lists/* 
fi

# Ensure agent-client-protocol (ACP) is installed
echo "[post-create-cmd.sh] Checking agent-client-protocol (ACP)..."
if command -v hermes &>/dev/null; then
  HERMES_VENV_PYTHON="$HOME/.hermes/hermes-agent/venv/bin/python"
  if [ -x "$HERMES_VENV_PYTHON" ]; then
    if ! "$HERMES_VENV_PYTHON" -c "import agent_client_protocol" 2>/dev/null; then
      echo "[post-create-cmd.sh] ACP not found, installing..."
      "$HERMES_VENV_PYTHON" -m pip install "agent-client-protocol>=0.9.0,<1.0"
    else
      echo "[post-create-cmd.sh] ACP already installed"
    fi
  fi
else
  echo "[post-create-cmd.sh] hermes not found, skipping ACP check"
fi

# Configure hermes defaults if first run
if command -v hermes &>/dev/null && [ -d "$HOME/.hermes/sessions" ] && [ -z "$(ls -A "$HOME/.hermes/sessions")" ]; then
    echo "[post-create-cmd.sh] No sessions found, setting up default configuration for custom provider"
    echo "[start-hermes] Initializing hermes config..."

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
    echo "[start-hermes] Installing Skill: memory-automation.md"
    mkdir -p "$HOME/.hermes/skills/memory-automation"
    cp ${SCRIPT_DIR}/skill-memory-automation.md "$HOME/.hermes/skills/memory-automation/SKILL.md"

fi

# Install modelrelay globally
# sudo npm install -g modelrelay@${MODELRELAY_VERSION} && \
sudo npm install github:gitricko/modelrelay -g --prefix /usr/local/lib/modelrelay
sudo ln -sf /usr/local/lib/modelrelay/bin/modelrelay /usr/local/bin/modelrelay
sudo npm cache clean --force

echo "[post-create-cmd.sh] Checking modelrelay..."
if command -v modelrelay &>/dev/null; then
  if pgrep -f modelrelay > /dev/null; then
    echo "[post-create-cmd.sh] modelrelay is already running, skipping"
  else
    echo "[post-create-cmd.sh] Starting modelrelay in the background..."
    setsid /usr/local/bin/modelrelay >> /tmp/modelrelay.log 2>&1 &
  fi
else
  echo "[post-create-cmd.sh] modelrelay not found, skipping start"
fi

# Install OmniRoute and start automatically when desktop loads
sudo npm install omniroute@${OMNIROUTE_VERSION} -g --prefix /usr/local/lib/omniroute
sudo ln -sf /usr/local/lib/omniroute/bin/omniroute /usr/local/bin/omniroute
sudo npm cache clean --force
# sudo mkdir -p /usr/local/lib/node_modules/omniroute/app/logs/application

echo "[post-create-cmd.sh] Checking omniroute..."
if command -v omniroute &>/dev/null; then
  if pgrep -f omniroute > /dev/null; then
    echo "[post-create-cmd.sh] omniroute is already running, skipping"
  else
    echo "[post-create-cmd.sh] Starting omniroute in the background..."
    setsid /usr/local/bin/omniroute >> /tmp/omniroute.log 2>&1 &
  fi
else
  echo "[post-create-cmd.sh] omniroute not found, skipping start"
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

# Install Cline with default configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[post-create-cmd.sh] Installing Cline with default configuration..."
mkdir -p "$HOME/.cline/data"
cp "${SCRIPT_DIR}/cline-globalState.json" "$HOME/.cline/data/globalState.json"
cp "${SCRIPT_DIR}/cline-secrets.json" "$HOME/.cline/data/secrets.json"
bash -c 'code --force --install-extension saoudrizwan.claude-dev'
npm install -g cline
