# ── Baked Devcontainer Image ──────────────────────────────────────────
# Pre-installs all heavy tooling so containers start in seconds, not minutes.
# Rebuild:  docker build -t hermes-codespace:latest -f .devcontainer/Dockerfile .
# ────────────────────────────────────────────────────────────────────────

FROM mcr.microsoft.com/devcontainers/base:ubuntu

# ── Versions (single source of truth) ─────────────────────────────────
ARG HERMES_VERSION=v2026.7.7.2
ARG OMNIROUTE_VERSION=3.8.48
ARG OLLAMA_VERSION=0.32.1
ARG NODE_VERSION=24.18.0
ARG MNEMON_VERSION=0.1.17

# Export as env so install scripts can see them
ENV OLLAMA_VERSION=${OLLAMA_VERSION}
ENV OLLAMA_NO_START=1
ENV DEBIAN_FRONTEND=noninteractive

# ── System packages + ALL heavy installs in ONE layer ──────────────────
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        zsh ripgrep jq curl git ca-certificates gnupg zstd \
    && rm -rf /var/lib/apt/lists/* \
    
    # ── Ollama ────────────────────────────────────────────────────────
    && curl -fsSL https://ollama.com/install.sh | sh \
    
    # ── Hermes Agent ─────────────────────────────────────────────────
    # Runs as root → FHS layout: code at /usr/local/lib/hermes-agent,
    # command at /usr/local/bin/hermes.  Node.js goes to $HERMES_HOME/node/
    # which is /root/.hermes/node/ during build (inaccessible to vscode user).
    # We relocate Node.js to /usr/local/lib/nodejs in the next layer.
    && curl -fsSL "https://raw.githubusercontent.com/NousResearch/hermes-agent/${HERMES_VERSION}/scripts/install.sh" \
        | bash -s -- --skip-setup \
    && npm cache clean --force \
    
    # ── agent-client-protocol (inside hermes venv) ────────────────────
    # FHS root layout puts venv at /usr/local/lib/hermes-agent/venv/
    # uv venvs don't include pip by default — ensurepip first, || true to
    # never break the && chain (non-critical package).
    && VENV_PYTHON="/usr/local/lib/hermes-agent/venv/bin/python" \
    && if [ ! -x "$VENV_PYTHON" ]; then VENV_PYTHON="$HOME/.hermes/hermes-agent/venv/bin/python"; fi \
    && if [ -x "$VENV_PYTHON" ]; then \
        "$VENV_PYTHON" -m ensurepip --upgrade 2>/dev/null || true; \
        "$VENV_PYTHON" -m pip install "agent-client-protocol>=0.9.0,<1.0" 2>/dev/null || true; \
    fi \
    
    # ── ModelRelay ────────────────────────────────────────────────────
    && npm install github:gitricko/modelrelay -g --prefix /usr/local/lib/modelrelay \
    && ln -sf /usr/local/lib/modelrelay/bin/modelrelay /usr/local/bin/modelrelay \
    && npm cache clean --force \
    
    # ── OmniRoute ─────────────────────────────────────────────────────
    && npm install omniroute@${OMNIROUTE_VERSION} -g --prefix /usr/local/lib/omniroute \
    && ln -sf /usr/local/lib/omniroute/bin/omniroute /usr/local/bin/omniroute \
    && npm cache clean --force \
    
    # ── OmniRoute dist/ dep repair (hollow deps workaround) ──────────
    && omni_root="/usr/local/lib/omniroute/lib/node_modules/omniroute" \
    && dist_nm="$omni_root/dist/node_modules" \
    && parent_nm="$omni_root/node_modules" \
    && if [ -d "$dist_nm" ]; then \
        for dst in $(find "$dist_nm" -mindepth 1 -maxdepth 1 -type d 2>/dev/null); do \
            rel="${dst#"$dist_nm"/}" \
            && src="$parent_nm/$rel" \
            && if [ -d "$src" ] && [ ! "$(find "$dst" \( -name '*.js' -o -name '*.mjs' -o -name '*.node' \) -type f 2>/dev/null | head -1)" ] \
                && [ "$(find "$src" \( -name '*.js' -o -name '*.mjs' -o -name '*.node' \) -type f 2>/dev/null | head -1)" ]; then \
                rm -rf "$dst" && cp -r "$src" "$dst" \
                && echo "Repaired hollow dep: $rel"; \
            fi; \
        done; \
    fi \
    
    # ── TailScale ─────────────────────────────────────────────────────
    && mkdir -p /var/run/tailscale /var/lib/tailscale \
    && (curl -fsSL https://tailscale.com/install.sh | sh || echo "WARN: tailscale install failed, continuing") \
    && rm -rf /var/lib/apt/lists/* \
    
    # ── Mnemon ────────────────────────────────────────────────────────
    && ARCH=amd64 \
    && curl -sL "https://github.com/mnemon-dev/mnemon/releases/download/v${MNEMON_VERSION}/mnemon_${MNEMON_VERSION}_linux_${ARCH}.tar.gz" \
        -o /tmp/mnemon.tar.gz \
    && tar xzf /tmp/mnemon.tar.gz -C /tmp \
    && cp /tmp/mnemon /usr/local/bin/mnemon \
    && chmod +x /usr/local/bin/mnemon \
    && rm -rf /tmp/mnemon.tar.gz /tmp/mnemon \
    
    # ── Cline ─────────────────────────────────────────────────────────
    && npm install -g cline \
    
    # ── Claude CLI ────────────────────────────────────────────────────
    && curl -fsSL https://claude.ai/install.sh | bash \
    
    # ── Final cleanup ─────────────────────────────────────────────────
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /root/.npm /tmp/* /var/tmp/* \
    && rm -rf /root/.cache/pip 2>/dev/null || true

# ── Relocate Node.js for non-root user access ──────────────────────────
# The hermes installer puts Node.js at $HERMES_HOME/node/ which resolves to
# /root/.hermes/node/ during build.  The devcontainer runs as the vscode user
# (uid 1000) who cannot traverse /root (drwx------).  We move Node.js to a
# system-wide location and re-point the symlinks.
RUN NODE_HERMES_DIR="$HOME/.hermes/node" \
    && NODE_SYSTEM_DIR="/usr/local/lib/nodejs" \
    && if [ -d "$NODE_HERMES_DIR" ]; then \
        mv "$NODE_HERMES_DIR" "$NODE_SYSTEM_DIR" \
        && ln -sf "$NODE_SYSTEM_DIR/bin/node"  /usr/local/bin/node \
        && ln -sf "$NODE_SYSTEM_DIR/bin/npm"   /usr/local/bin/npm \
        && ln -sf "$NODE_SYSTEM_DIR/bin/npx"   /usr/local/bin/npx \
        && mkdir -p "$NODE_SYSTEM_DIR/etc" \
        && printf 'prefix=/usr/local\n' > "$NODE_SYSTEM_DIR/etc/npmrc" \
        && echo "Node.js relocated to $NODE_SYSTEM_DIR"; \
    fi

# ── Ensure hermes venv is world-readable ───────────────────────────────
# FHS root layout places the venv at /usr/local/lib/hermes-agent/venv/.
# Some sub-directories may be mode 700 (root-only).  Make them traversable
# so the vscode user can exec hermes and its bundled Python.
RUN chmod -R a+rX /usr/local/lib/hermes-agent 2>/dev/null || true \
    && chmod -R a+rX /usr/local/lib/nodejs 2>/dev/null || true

# ── Make claude CLI accessible if installed to /root ───────────────────
# The claude.ai installer may put the binary under $HOME/.local/bin/.
# Create a symlink in /usr/local/bin/ so all users can find it.
RUN CLAUDE_BIN="$(find /root/.local /usr/local -name claude -type f 2>/dev/null | head -1)" \
    && if [ -n "$CLAUDE_BIN" ] && [ ! -x "/usr/local/bin/claude" ]; then \
        ln -sf "$CLAUDE_BIN" /usr/local/bin/claude \
        && echo "claude CLI linked from $CLAUDE_BIN"; \
    fi

# ── Copy config files ─────────────────────────────────────────────────
COPY .devcontainer/CLAUDE.md /tmp/devcontainer-config/CLAUDE.md
COPY .devcontainer/claude-term-settings.json /tmp/devcontainer-config/claude-term-settings.json
COPY .devcontainer/.claude.json /tmp/devcontainer-config/.claude.json
COPY .devcontainer/skill-memory-automation.md /tmp/devcontainer-config/skill-memory-automation.md
COPY .devcontainer/.hermes.md /tmp/devcontainer-config/.hermes.md
COPY .devcontainer/cline-globalState.json /tmp/devcontainer-config/cline-globalState.json
COPY .devcontainer/cline-secrets.json /tmp/devcontainer-config/cline-secrets.json
COPY .devcontainer/self-check.sh /usr/local/bin/self-check.sh

# ── Entrypoint: lightweight service start + config placement ──────────
COPY .devcontainer/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/self-check.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
