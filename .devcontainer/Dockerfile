# ── Baked Devcontainer Image ──────────────────────────────────────────
# Pre-installs all heavy tooling so containers start in seconds, not minutes.
# Rebuild:  docker build -t hermes-codespace:latest -f .devcontainer/Dockerfile .
# ──────────────────────────────────────────────────────────────────────

FROM mcr.microsoft.com/devcontainers/base:ubuntu

# ── Versions (single source of truth) ────────────────────────────────
ARG HERMES_VERSION=v2026.7.7.2
ARG OMNIROUTE_VERSION=3.8.48
ARG OLLAMA_VERSION=0.32.1
ARG NODE_VERSION=24.18.0
ARG MNEMON_VERSION=0.1.17

# ── System packages ──────────────────────────────────────────────────
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        zsh ripgrep jq curl git ca-certificates gnupg \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js (required by npm installs below) ─────────────────────────
# The devcontainer base already has Node, but pin if needed:
# RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
#     && apt-get install -y nodejs

# ── Ollama ────────────────────────────────────────────────────────────
RUN curl -fsSL https://ollama.com/install.sh | sh

# ── Hermes Agent ──────────────────────────────────────────────────────
RUN curl -fsSL "https://raw.githubusercontent.com/NousResearch/hermes-agent/${HERMES_VERSION}/scripts/install.sh" \
    | bash -s -- --skip-setup \
    && npm cache clean --force \
    && rm -rf /var/lib/apt/lists/*

# ── agent-client-protocol (inside hermes venv) ───────────────────────
RUN if [ -x "$HOME/.hermes/hermes-agent/venv/bin/python" ]; then \
        "$HOME/.hermes/hermes-agent/venv/bin/python" -m pip install "agent-client-protocol>=0.9.0,<1.0" ; \
    fi

# ── ModelRelay ────────────────────────────────────────────────────────
RUN npm install github:gitricko/modelrelay -g --prefix /usr/local/lib/modelrelay \
    && ln -sf /usr/local/lib/modelrelay/bin/modelrelay /usr/local/bin/modelrelay \
    && npm cache clean --force

# ── OmniRoute ─────────────────────────────────────────────────────────
RUN npm install omniroute@${OMNIROUTE_VERSION} -g --prefix /usr/local/lib/omniroute \
    && ln -sf /usr/local/lib/omniroute/bin/omniroute /usr/local/bin/omniroute \
    && npm cache clean --force

# ── OmniRoute dist/ dep repair (workaround for hollow bundled deps) ──
RUN omni_root="/usr/local/lib/omniroute/lib/node_modules/omniroute" \
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
    fi

# ── TailScale ─────────────────────────────────────────────────────────
RUN mkdir -p /var/run/tailscale /var/lib/tailscale \
    && curl -fsSL https://tailscale.com/install.sh | sh \
    && rm -rf /var/lib/apt/lists/*

# ── Mnemon ────────────────────────────────────────────────────────────
RUN ARCH=amd64 \
    && curl -sL "https://github.com/mnemon-dev/mnemon/releases/download/v${MNEMON_VERSION}/mnemon_${MNEMON_VERSION}_linux_${ARCH}.tar.gz" \
       -o /tmp/mnemon.tar.gz \
    && tar xzf /tmp/mnemon.tar.gz -C /tmp \
    && cp /tmp/mnemon /usr/local/bin/mnemon \
    && chmod +x /usr/local/bin/mnemon \
    && rm -rf /tmp/mnemon.tar.gz /tmp/mnemon

# ── Cline ─────────────────────────────────────────────────────────────
RUN npm install -g cline

# ── Claude CLI ────────────────────────────────────────────────────────
RUN curl -fsSL https://claude.ai/install.sh | bash

# ── Copy config files ────────────────────────────────────────────────
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
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
