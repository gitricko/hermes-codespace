# Hermes-CodeSpace

A GitHub project starter template with pre-installed AI coding tools. Built on [devcontainers](https://containers.dev/) — ready to clone, fork, or use as a template for any new repository. (actually, it is just the `.devcontainer` directory)

## Read this if reading this README.md in codespace

### First-time setup
When creating this codespace for the first time, the setup process will:
- **PostCreateCMD**: Install and configure Hermes and its associated OSS software (listed below)
- Start default services: Hermes Gateway, Dashboard, Ollama, and free LLM proxies (OmniRoute and ModelRelay)
- Take 5-10 minutes to complete

You can verify everything is ready by checking the **PORTS** panel in the lower sidebar. You should see ports: **7352**, **11434**, **20128**, and **9119**.

### Existing codespace
If you're using an existing codespace, startup will be faster since installation is already complete. The system will only start the services.

### Checking setup/start-up progress
Logs for container creation (which is 1 time) or start up is in this path: `/tmp/hermes-codespace.log`. You can use this command in terminal to view the file. `code /tmp/hermes-codespace.log`

## What's included

| Component | Purpose |
|-----------|---------|
| **[Hermes Agent](https://github.com/nousresearch/hermes-agent)** | AI coding assistant with memory, skills, and multi-step task execution |
| **[Hermes VS Code Extension](https://marketplace.visualstudio.com/items?itemName=JoveRina.rina-hermes-acp)** | Full IDE integration — chat, inline suggestions, and terminal access directly in VS Code |
| **[ModelRelay](https://www.npmjs.com/package/modelrelay)** | OpenAI-compatible local router — benchmarks free coding models and routes requests to the best available provider |
| **[OmniRoute](https://www.npmjs.com/package/modelrelay)** | OpenAI-compatible local router — benchmarks free coding models and routes requests to the best available provider |
| **[Claude CLI and VS Code Extension](https://marketplace.visualstudio.com/items?itemName=anthropic.claude-code)** | Additional Agent: Claude in your IDE, capable of creating/editing files, running commands, using the browser. Also preconfigured with ModelRelay by default |
| **[Cline — VS Code Extension](https://marketplace.visualstudio.com/items?itemName=saoudrizwan.claude-dev)** | Additional Agent: Cline coding agent right in your IDE, capable of creating/editing files, running commands, using the browser. Also preconfigured with ModelRelay by default |

![Hermes in action](.devcontainer/screen-shot.png)

## Why

GitHub Copilot is great — until your free trial ends. Hermes-CodeSpace gives you a self-hosted alternative that runs in your dev container with zero configuration.

## Quick start

1. **Fork the repo** → Click "Fork" on GitHub (or copy folder `.devcontainer` into your repo)
2. **Open in Codespace** → Green button → Done
3. **Start coding** → Hermes is ready in the terminal with free models enabled (takes a minute or 2 if it is a fresh codespace)

**Want more models?** Open the ModelRelay dashboard via the Codespace Ports panel (`localhost:7352`) to add providers.

## Local development

Prefer to run locally instead of in the cloud? Check out [hermes-webtop](https://github.com/gitricko/hermes-webtop) for a Docker-based setup that runs on your own machine.

## Forking & Going Private

Forked repositories on GitHub are public by default. If you want to keep your setup private, follow these steps:

### 1. Leave the Fork Network

1. Go to your forked repository on GitHub → **Settings**
2. Scroll down to the **Danger Zone** section
3. Click **Leave fork network**
4. Confirm the action

### 2. Change Visibility to Private

Once unlinked, the **Change visibility** button becomes available in the Danger Zone:
1. Click **Change visibility**
2. Select **Private**
3. Confirm

### 3. Receiving Future Updates

After converting to private, you can still pull updates from this upstream repository:

```bash
cd .devcontainer && make update-deps
```

**What this does:**
- Preserves your files — any custom files you created remain untouched
- Syncs matching files — updates from upstream overwrite existing files in `.devcontainer/`
- Excludes hidden files — `.git/`, `.env`, and other hidden files are protected

**Best practice:** Always review changes before committing:
```bash
git diff .devcontainer/    # Review what's changed
git status                 # See what will be committed
```

## License

MIT — see [LICENSE](LICENSE)
