# CDP Browser Testing in Codespaces

## Overview

GitHub Codespaces don't have system Chrome/Chromium installed. The `browser_use` tool's built-in browser fails to launch. Playwright installs its own Chromium to `~/.cache/ms-playwright/chromium-*/chrome-linux64/chrome` — we can drive it via CDP (Chrome DevTools Protocol) on port 9222.

This article documents the reference architecture for headless browser automation in Codespaces using Playwright's bundled Chromium and CDP.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Codespace Environment                     │
│                                                              │
│  ┌──────────────┐     CDP (port 9222)      ┌─────────────┐  │
│  │  CDPClient   │ ◄──────────────────────► │  Chromium   │  │
│  │  (Python)    │   WebSocket + HTTP       │  (Playwright│  │
│  └──────────────┘                          │   cached)   │  │
│        ▲                                   └─────────────┘  │
│        │                                          ▲          │
│        │ launch-chrome-cdp.sh                      │          │
│        └──────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

## Key Components

### 1. Playwright Chromium Cache

Playwright downloads its own Chromium binary on first use:
- Location: `~/.cache/ms-playwright/chromium-*/chrome-linux64/chrome`
- Version: Tracked in Playwright's package.json
- No system Chrome dependency required

### 2. CDP Launcher Script

`launch-chrome-cdp.sh`:
- Finds the cached Playwright Chromium binary
- Starts headless Chrome with `--remote-debugging-port=9222`
- Prints the WebSocket URL for CDP connection
- Sets `CDP_WS_URL` environment variable

```bash
source ~/.hermes/skills/codespace/cdp-browser-testing/scripts/launch-chrome-cdp.sh
# Sets CDP_WS_URL=ws://127.0.0.1:9222/devtools/browser/<uuid>
```

### 3. CDPClient Python Module

`cdp_client.py` — Async Python class providing:
- `connect()` — Auto-discovers browser via `http://127.0.0.1:9222/json/version`
- `new_page()` — Creates a new browser tab
- `navigate(url)` — Navigates to URL
- `wait_for(selector)` — JS-based wait (React-safe)
- `type_text(selector, text)` — Types into input via Runtime.evaluate
- `click(selector)` — Clicks element via Runtime.evaluate
- `get_html(selector?)` — Full or scoped outerHTML
- `get_text(selector)` — textContent of element
- `evaluate(js_expression)` — Any JS expression
- `get_chat_bubbles()` — Lavish-axi chat turn extraction

### 4. React-Safe Interaction

**Critical**: CDP `DOM.querySelector` is unreliable against React apps — it often returns no nodeId.

The solution: Use `Runtime.evaluate` for all interactions:
- `wait_for()` polls via `document.querySelector` in page context
- `type_text()` and `click()` dispatch events via `Runtime.evaluate`
- `get_chat_bubbles()` extracts lavish-axi turns via page JS

## Usage Patterns

### Basic Navigation & Interaction

```python
from cdp_client import CDPClient

async with CDPClient() as cdp:
    await cdp.navigate('http://127.0.0.1:4387/session/xxx')
    await cdp.wait_for('#chatInput')
    await cdp.type_text('#chatInput', 'Hello from agent!')
    await cdp.click('#send')
    bubbles = await cdp.get_chat_bubbles()
    print(bubbles)
```

### Data Extraction

```python
html = await cdp.get_html()              # Full document outerHTML
html = await cdp.get_html('#artifact')    # Scoped outerHTML
text = await cdp.get_text('h1')           # textContent of element
val  = await cdp.evaluate("1 + 1")        # Any JS expression
```

## Troubleshooting Reference

| Issue | Cause | Resolution |
|-------|-------|------------|
| Chrome won't start | Playwright Chromium not installed | Run `playwright install chromium` |
| Port 9222 busy | Existing chrome process | `pkill -f "remote-debugging-port=9222"` |
| Navigation hangs | Orphaned CDP targets from previous run | Kill all chrome processes, relaunch |
| Element not found | CDP DOM.querySelector fails on React | Use `wait_for()` + `type_text()`/`click()` (Runtime.evaluate) |
| ModuleNotFoundError | Import as `cdp_client` not `cdp-client` | Ensure script dir on PYTHONPATH |
| Mermaid not rendering | Missing Mermaid CDN script in artifact | Add Mermaid ES module import + initialize |
| Whiteboard cookie error | Excalidraw iframe sandboxed without allow-same-origin | By design — static flowchart works, editor doesn't |

## Related

- **Skill**: `.devcontainer/skills/cdp-browser-testing/` — Procedural how-to
- **Wiki**: [github-codespace.md](github-codespace.md) — Codespace auth for CI
- **Wiki**: [codespace-port-visibility.md](codespace-port-visibility.md) — Exposing ports for browser access
- **Wiki**: [lavish-axi-codespace-setup.md](lavish-axi-codespace-setup.md) — Full lavish-axi setup with CDP

## When to Use This Pattern

- Headless browser testing in GitHub Codespaces (no system Chrome)
- Automating lavish-axi or similar localhost web UIs over loopback
- Any CDP-driven browser automation where Playwright Chromium is available
- CI/CD pipelines in Codespaces needing browser verification