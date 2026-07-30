# ── Baked Devcontainer Image ──────────────────────────────────────────
# Pre-installs all heavy tooling so containers start in seconds, not minutes.
# Rebuild:  docker build -t hermes-codespace:latest -f .devcontainer/Dockerfile .
# ────────────────────────────────────────────────────────────────────────

FROM mcr.microsoft.com/devcontainers/base:ubuntu

# ── Versions (single source of truth) ─────────────────────────────────
ARG HERMES_VERSION=v2026.7.20
ARG OMNIROUTE_VERSION=3.8.49
ARG OLLAMA_VERSION=0.32.5
ARG NODE_VERSION=24.18.0
ARG MNEMON_VERSION=0.1.17

# Export as env so install scripts can see them
ENV OLLAMA_VERSION=${OLLAMA_VERSION}
ENV OLLAMA_NO_START=1
ENV DEBIAN_FRONTEND=noninteractive

# ── System packages + ALL heavy installs in ONE layer ──────────────────
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        zsh ripgrep jq curl git ca-certificates gnupg zstd sudo \
        python3 python3-pip nodejs npm \
    && rm -rf /var/lib/apt/lists/* \
    \

    # ── Ensure a non-root user with UID 1000 exists ──────────────────────
    # Universal base image may already have a UID-1000 user (e.g. "codespace").
    # Find the existing name if any, otherwise create "vscode".
    && UID1000_USER=$(getent passwd 1000 | cut -d: -f1) \
    && if [ -z "$UID1000_USER" ]; then \
        (getent group 1000 >/dev/null || groupadd --gid 1000 vscode) \
        && useradd --uid 1000 --gid 1000 -m -s /bin/bash vscode \
        && UID1000_USER=vscode; \
    fi \
    && echo "${UID1000_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vscode \
    && chmod 0440 /etc/sudoers.d/vscode \
    \

    # ── Ollama ────────────────────────────────────────────────────────
    && curl -fsSL https://ollama.com/install.sh | bash \
    \
    # ── Bake Ollama embedding model into image ───────────────────────
    # Pull nomic-embed-text at build time so it's available instantly
    # at runtime with zero RAM spike or download delay. (~300MB)
    # Ensure full directory tree exists with proper permissions for vscode user
    && mkdir -p /usr/share/ollama/.ollama/models \
    && chmod -R a+rwX /usr/share/ollama/.ollama \
    && chmod a+rx /usr/share/ollama \
    && OLLAMA_HOST=0.0.0.0 OLLAMA_MODELS=/usr/share/ollama/.ollama/models ollama serve & \
    for i in 1 2 3 4 5; do sleep 5; curl -sf http://localhost:11434/api/tags && break; done; \
    OLLAMA_MODELS=/usr/share/ollama/.ollama/models /usr/local/bin/ollama pull nomic-embed-text && \
    ls -la /usr/share/ollama/.ollama/models/ && \
    find /usr/share/ollama/.ollama/models -type f | head -20 && \
    OLLAMA_MODELS=/usr/share/ollama/.ollama/models ollama list && \
    kill %1 && wait 2>/dev/null || true \
    \
    # ── Hermes Agent ─────────────────────────────────────────────────
    # Runs as root → FHS layout: code at /usr/local/lib/hermes-agent,
    # command at /usr/local/bin/hermes.  Node.js goes to $HERMES_HOME/node/
    # which is /root/.hermes/node/ during build (inaccessible to vscode user).
    # We relocate Node.js to /usr/local/lib/nodejs in the next layer.
    && curl -fsSL "https://raw.githubusercontent.com/NousResearch/hermes-agent/${HERMES_VERSION}/scripts/install.sh" \
        | bash -s -- --skip-setup \
    && npm cache clean --force \
    \

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
    \

    # ── ModelRelay ────────────────────────────────────────────────────
    && npm install github:gitricko/modelrelay -g --prefix /usr/local/lib/modelrelay \
    && ln -sf /usr/local/lib/modelrelay/bin/modelrelay /usr/local/bin/modelrelay \
    && npm cache clean --force \
    \

    # ── OmniRoute ─────────────────────────────────────────────────────
    && npm install omniroute@${OMNIROUTE_VERSION} -g --prefix /usr/local/lib/omniroute \
    && ln -sf /usr/local/lib/omniroute/bin/omniroute /usr/local/bin/omniroute \
    && npm cache clean --force \
    \

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
    \

    # ── TailScale ─────────────────────────────────────────────────────
    && mkdir -p /var/run/tailscale /var/lib/tailscale \
    && (curl -fsSL https://tailscale.com/install.sh | bash || echo "WARN: tailscale install failed, continuing") \
    && rm -rf /var/lib/apt/lists/* \
    \

    # ── Mnemon ────────────────────────────────────────────────────────
    && ARCH=amd64 \
    && curl -sL "https://github.com/mnemon-dev/mnemon/releases/download/v${MNEMON_VERSION}/mnemon_${MNEMON_VERSION}_linux_${ARCH}.tar.gz" \
        -o /tmp/mnemon.tar.gz \
    && tar xzf /tmp/mnemon.tar.gz -C /tmp \
    && cp /tmp/mnemon /usr/local/bin/mnemon \
    && chmod +x /usr/local/bin/mnemon \
    && rm -rf /tmp/mnemon.tar.gz /tmp/mnemon \
    \

    # ── Build Hermes Web UI
    # The installer places source at /root/.hermes/hermes-agent/web (FHS layout)
    # or /usr/local/lib/hermes-agent/web. Build outputs to hermes_cli/web_dist.
    # After build, remove node_modules to save ~3.5GB (electron etc.) — only
    # the built web_dist output is needed at runtime.
    && if [ -d "/root/.hermes/hermes-agent/web" ]; then \
        cd /root/.hermes/hermes-agent/web && npm install --silent && npm run build \
        && rm -rf node_modules; \
    elif [ -d "/usr/local/lib/hermes-agent/web" ]; then \
        cd /usr/local/lib/hermes-agent/web && npm install --silent && npm run build \
        && rm -rf node_modules; \
    else \
        echo "WARN: Hermes web source not found, skipping web UI build"; \
    fi \
    && curl -fsSL https://claude.ai/install.sh | bash \
    \

    # ── Final cleanup ─────────────────────────────────────────────────
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /root/.npm /tmp/* /var/tmp/* \
    && rm -rf /root/.cache/pip 2>/dev/null || true \
    # Ensure Ollama model directory and all parent dirs are writable by vscode user
    && mkdir -p /usr/share/ollama/.ollama/models \
    && chmod -R a+rwX /usr/share/ollama/.ollama \
    # Ensure /usr/share/ollama itself is traversable by vscode user
    && chmod a+rx /usr/share/ollama

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
COPY .devcontainer/CLAUDE.md /usr/local/share/devcontainer-config/CLAUDE.md
COPY .devcontainer/claude-term-settings.json /usr/local/share/devcontainer-config/claude-term-settings.json
COPY .devcontainer/.claude.json /usr/local/share/devcontainer-config/.claude.json
COPY .devcontainer/skill-memory-automation.md /usr/local/share/devcontainer-config/skill-memory-automation.md
COPY .devcontainer/.hermes.md /usr/local/share/devcontainer-config/.hermes.md
COPY .devcontainer/cline-globalState.json /usr/local/share/devcontainer-config/cline-globalState.json
COPY .devcontainer/cline-secrets.json /usr/local/share/devcontainer-config/cline-secrets.json
COPY .devcontainer/self-check.sh /usr/local/bin/self-check.sh

# ── Entrypoint: lightweight service start + config placement ──────────
COPY .devcontainer/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/self-check.sh

# ── Switch to non-root user (by UID, works with any username) ────────────
USER 1000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
