#!/bin/bash

HERMES_VERSION="v2026.7.7.2"
OMNIROUTE_VERSION=3.8.48
MODELRELAY_VERSION=1.18.0
OLLAMA_VERSION=0.32.0
NODE_VERSION=24.18.0
MNEMON_VERSION=0.1.17

sudo apt-get update && sudo apt-get install -y htop zsh ripgrep gh remmina iputils-ping net-tools socat && sudo rm -rf /var/lib/apt/lists/*

# InstallNode.js binaries and libraries

# Install the Ollama binary from the official image
curl -fsSL https://ollama.com/install.sh | sh

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
  hermes config set model.provider custom
  hermes config set model.base_url http://localhost:7352/v1
  hermes config set model.default auto-fastest
fi

# Install modelrelay globally
sudo npm install modelrelay -g --prefix /usr/local/lib/modelrelay
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

# Install Cline with default configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[post-create-cmd.sh] Installing Cline with default configuration..."
mkdir -p "$HOME/.cline/data"
cp "${SCRIPT_DIR}/globalState.json" "$HOME/.cline/data/globalState.json"
cp "${SCRIPT_DIR}/secrets.json" "$HOME/.cline/data/secrets.json"
bash -c 'code --force --install-extension saoudrizwan.claude-dev'
npm install -g cline

