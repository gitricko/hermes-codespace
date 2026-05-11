#!/bin/bash

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

# Install ripgrep for better search performance in hermes-agent
if ! command -v rg &>/dev/null; then
  echo "[post-create-cmd.sh] Installing ripgrep for better search performance in hermes-agent..."
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    cd /tmp
    curl -LO https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep_14.1.1-1_amd64.deb
    sudo dpkg -i ripgrep_14.1.1-1_amd64.deb
    rm ripgrep_14.1.1-1_amd64.deb
  fi
fi

# Install hermes-agent
HERMES_VERSION="v2026.5.7"
curl -fsSL "https://raw.githubusercontent.com/NousResearch/hermes-agent/${HERMES_VERSION}/scripts/install.sh" | bash -s -- --skip-setup
npm cache clean --force
sudo rm -rf /var/lib/apt/lists/* 

# Configure hermes defaults if first run
if command -v hermes &>/dev/null && [ -d "$HOME/.hermes/sessions" ] && [ -z "$(ls -A "$HOME/.hermes/sessions")" ]; then
  echo "[post-create-cmd.sh] No sessions found, setting up default configuration for custom provider"
  hermes config set model.provider custom
  hermes config set model.base_url http://localhost:7352/v1
  hermes config set model.default auto-fastest
fi
