# ── Baked Devcontainer Image ──────────────────────────────────────────
# Pre-installs all heavy tooling so containers start in seconds, not minutes.
# Rebuild:  docker build -t hermes-codespace:latest -f .devcontainer/Dockerfile .
# ────────────────────────────────────────────────────────────────────────

# ── Ollama version (only needed for the FROM instruction) ───────────────
ARG OLLAMA_VERSION=0.32.5

# Use the official Ollama image to get the binary
FROM ollama/ollama:${OLLAMA_VERSION} AS ollama-bin

# ── Node.js builder: ModelRelay + OmniRoute + Hermes Web UI + TUI ───────
FROM node:24-slim AS node-builder

ARG OMNIROUTE_VERSION
ARG HERMES_VERSION

# Install git for GitHub-based npm installs and configure HTTPS
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"

# ── ModelRelay ────────────────────────────────────────────────────────
RUN npm install github:gitricko/modelrelay -g --prefix /build/modelrelay

# ── OmniRoute ─────────────────────────────────────────────────────────
RUN npm install omniroute@${OMNIROUTE_VERSION} -g --prefix /build/omniroute

# ── OmniRoute dist/ dep repair (hollow deps workaround) ──────────────
RUN omni_root="/build/omniroute/lib/node_modules/omniroute" \
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

# ── Hermes Web UI ─────────────────────────────────────────────────────
# Build output lands at hermes_cli/web_dist relative to the repo root,
# NOT relative to the web/ directory.  So from web/ it's ../hermes_cli/web_dist
RUN git clone --depth 1 --branch ${HERMES_VERSION} https://github.com/NousResearch/hermes-agent.git /tmp/hermes \
    && cd /tmp/hermes/web \
    && npm install --silent \
    && npm run build \
    && cp -r ../hermes_cli/web_dist /build/web_dist \
    && rm -rf /tmp/hermes

# ── Hermes TUI ────────────────────────────────────────────────────────
# Build the TUI bundle (dist/entry.js) and copy to hermes_cli/tui_dist
# so the dashboard's embedded chat tab can spawn the TUI without a full workspace
RUN git clone --depth 1 --branch ${HERMES_VERSION} https://github.com/NousResearch/hermes-agent.git /tmp/hermes-tui \
    && cd /tmp/hermes-tui/ui-tui \
    && npm install --silent \
    && npm run build \
    && mkdir -p /build/tui_dist \
    && cp dist/entry.js /build/tui_dist/ \
    && rm -rf /tmp/hermes-tui

# ── Python builder: Hermes Agent venv ────────────────────────────────────
# Using 3.11-slim because hermes-agent requires Python >=3.11.
# We copy the full Python 3.11 runtime into the final image so venv works.
FROM python:3.11-slim AS python-builder

ARG HERMES_VERSION

# Install git for cloning hermes-agent repo
RUN apt-get update && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

# Clone hermes-agent source (separate RUN so the prebuilt bundles can be
# injected into the tree BEFORE pip install below)
RUN git clone --depth 1 --branch ${HERMES_VERSION} https://github.com/NousResearch/hermes-agent.git /tmp/hermes

# Inject the prebuilt TUI bundle into the source tree before `pip install .`.
# pyproject.toml declares tui_dist/**/* as package-data, so with the bundle
# present the wheel is built WITH it and the venv becomes self-contained —
# the dashboard's embedded chat PTY resolves hermes_cli/tui_dist/entry.js
# at runtime, and no last-minute copy into site-packages is needed.
COPY --from=node-builder /build/tui_dist/ /tmp/hermes/hermes_cli/tui_dist/

# Build Hermes Agent Python venv (non-editable so venv is self-contained)
# IMPORTANT: venv path must match COPY destination in final stage for shebangs to work
RUN mkdir -p /usr/local/lib/hermes-agent \
    && cd /tmp/hermes \
    && python -m venv /usr/local/lib/hermes-agent/venv \
    && /usr/local/lib/hermes-agent/venv/bin/pip install --no-cache-dir . \
    && /usr/local/lib/hermes-agent/venv/bin/pip install --no-cache-dir ".[acp]" \
    && /usr/local/lib/hermes-agent/venv/bin/hermes acp --check \
    && rm -rf /tmp/hermes

# ── Final stage ────────────────────────────────────────────────────────
FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Tool versions — passed from workflow via --build-arg (single source of truth)
ARG HERMES_VERSION
ARG OMNIROUTE_VERSION
ARG NODE_VERSION
ARG MNEMON_VERSION

# Export as env so install scripts can see them
ENV OLLAMA_VERSION=${OLLAMA_VERSION}
ENV OLLAMA_NO_START=1
ENV DEBIAN_FRONTEND=noninteractive

# Copy the Ollama binary from the official image
COPY --from=ollama-bin --chown=1000:1000 /usr/bin/ollama /usr/local/bin/ollama

# ── System packages + ALL heavy installs in ONE layer ──────────────────.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        zsh ripgrep jq curl git ca-certificates gnupg zstd sudo \
        python3 python3-pip nodejs npm \
    && rm -rf /var/lib/apt/lists/* \
    
    # ── Ensure a non-root user with UID 1000 exists ──────────────────────
    && UID1000_USER=$(getent passwd 1000 | cut -d: -f1) \
    && if [ -z "$UID1000_USER" ]; then \
        (getent group 1000 >/dev/null || groupadd --gid 1000 vscode) \
        && useradd --uid 1000 --gid 1000 -m -s /bin/bash vscode \
        && UID1000_USER=vscode; \
    fi \
    && echo "${UID1000_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vscode \
    && chmod 0440 /etc/sudoers.d/vscode \
    
    # ── Ollama (direct binary install – reliable in Docker) ───────────
    && ollama --version \
    
    # ── Bake Ollama embedding model into image ───────────────────────
    # Pull nomic-embed-text at build time so it's available instantly
    # at runtime with zero RAM spike or download delay. (~300MB)
    # Ensure full directory tree exists with proper permissions for vscode user
    && mkdir -p /usr/share/ollama/.ollama/models \
    && chmod -R a+rwX /usr/share/ollama/.ollama \
    && chmod a+rx /usr/share/ollama \
    && OLLAMA_HOST=0.0.0.0 OLLAMA_MODELS=/usr/share/ollama/.ollama/models ollama serve & \
    for i in 1 2 3 4 5; do sleep 10; curl -sf http://localhost:11434/api/tags && break; done; \
    OLLAMA_MODELS=/usr/share/ollama/.ollama/models /usr/local/bin/ollama pull nomic-embed-text && \
    ls -la /usr/share/ollama/.ollama/models/ && \
    find /usr/share/ollama/.ollama/models -type f | head -20 && \
    OLLAMA_MODELS=/usr/share/ollama/.ollama/models ollama list && \
    kill %1 && wait 2>/dev/null || true \
    \
    # ── TailScale ─────────────────────────────────────────────────────
    && mkdir -p /var/run/tailscale /var/lib/tailscale \
    && (curl -fsSL https://tailscale.com/install.sh | bash || echo "WARN: tailscale install failed, continuing") \
    && rm -rf /var/lib/apt/lists/* \
    

    # ── Mnemon ────────────────────────────────────────────────────────
    && ARCH=amd64 \
    && curl -sL "https://github.com/mnemon-dev/mnemon/releases/download/v${MNEMON_VERSION}/mnemon_${MNEMON_VERSION}_linux_${ARCH}.tar.gz" \
        -o /tmp/mnemon.tar.gz \
    && tar xzf /tmp/mnemon.tar.gz -C /tmp \
    && cp /tmp/mnemon /usr/local/bin/mnemon \
    && chmod +x /usr/local/bin/mnemon \
    && rm -rf /tmp/mnemon.tar.gz /tmp/mnemon \
    

    && curl -fsSL https://claude.ai/install.sh | bash \
    

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

# ── Copy Node.js packages from builder stage ──────────────────────────
COPY --from=node-builder /build/modelrelay/ /usr/local/lib/modelrelay/
COPY --from=node-builder /build/omniroute/ /usr/local/lib/omniroute/
# The venv's non-editable install puts hermes_cli in site-packages, so
# web_dist must go there for the dashboard --skip-build to find it.
COPY --from=node-builder /build/web_dist/ /usr/local/lib/hermes-agent/venv/lib/python3.11/site-packages/hermes_cli/web_dist/

# ── Copy Hermes Agent venv from python-builder ────────────────────────
# Non-editable install: venv is self-contained, no source tree needed.
# Venv was built at /usr/local/lib/hermes-agent/venv — same path in final image.
COPY --from=python-builder /usr/local/lib/hermes-agent/venv/ /usr/local/lib/hermes-agent/venv/

# ── Install Python 3.11 (required by hermes-agent and the venv) ──────
# The venv was built in python:3.11-slim which puts python at /usr/local/bin/python3.11.
# deadsnakes PPA installs to /usr/bin/python3.11, so symlink for compatibility.
RUN apt-get update \
    && apt-get install -y --no-install-recommends software-properties-common \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y --no-install-recommends python3.11 python3.11-venv \
    && ln -sf /usr/bin/python3.11 /usr/local/bin/python3.11 \
    && ln -sf /usr/bin/python3.11 /usr/local/bin/python \
    && rm -rf /var/lib/apt/lists/*

# ── Create symlinks for Node.js packages ──────────────────────────────
RUN ln -sf /usr/local/lib/modelrelay/bin/modelrelay /usr/local/bin/modelrelay \
    && ln -sf /usr/local/lib/omniroute/bin/omniroute /usr/local/bin/omniroute

# ── Create hermes symlink from python-builder venv ────────────────────
RUN ln -sf /usr/local/lib/hermes-agent/venv/bin/hermes /usr/local/bin/hermes

# ── Ensure hermes venv is world-readable ───────────────────────────────
# FHS root layout places the venv at /usr/local/lib/hermes-agent/venv/.
# Some sub-directories may be mode 700 (root-only).  Make them traversable
# so the vscode user can exec hermes and its bundled Python.  The venv is
# also made group/other-WRITABLE so the VS Code extension's ACP dependency
# repair flow (pip install into the venv as the vscode user) can succeed
# without sudo — this is a devcontainer, not a hardened prod image.
RUN chmod -R a+rX /usr/local/lib/hermes-agent 2>/dev/null || true \
    && chmod -R a+rwX /usr/local/lib/hermes-agent/venv 2>/dev/null || true \
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
