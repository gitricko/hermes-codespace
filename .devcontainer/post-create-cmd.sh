#!/bin/bash

sudo npm install modelrelay -g --prefix /usr/local/lib/modelrelay
sudo ln -s /usr/local/lib/modelrelay/bin/modelrelay /usr/local/bin/modelrelay
sudo npm cache clean --force
echo "[post-create-cmd.sh] Starting modelrelay in the background..."
touch /tmp/modelrelay.log
nohup /usr/local/bin/modelrelay >> /tmp/modelrelay.log 2>&1 &

curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash -s -- --skip-setup && \
    npm cache clean --force && \
    sudo rm -rf /var/lib/apt/lists/* 

if [ -d "$HOME/.hermes/sessions" ] && [ -z "$(ls -A "$HOME/.hermes/sessions")" ]; then
  echo "[start-1-hermes.sh] No sessions found in $HOME/.hermes/sessions, setting up default configuration for custom provider"
  hermes config set model.provider custom && hermes config set model.base_url http://localhost:7352/v1 && hermes config set model.default auto-fastest
fi

