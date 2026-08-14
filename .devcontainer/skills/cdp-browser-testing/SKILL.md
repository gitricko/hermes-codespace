---
name: cdp-browser-testing
description: Headless browser automation in Codespaces w/ Playwright CDP.
trigger: Use when you need headless browser automation in Codespaces without system Chrome.
category: codespace
version: 1.1.0
author: hermes-agent
license: MIT
tags:
  - codespace
  - browser
  - cdp
  - playwright
  - testing
related_skills:
  - codespace/github-codespace
  - codespace/persistent-knowledge
---

# CDP Browser Testing Skill

## When to Use
- Headless browser testing in GitHub Codespaces (no system Chrome)
- Automating lavish-axi or similar localhost web UIs over loopback
- Any CDP-driven browser automation where Playwright Chromium is available
- CI/CD pipelines in Codespaces needing browser verification

## Problem
GitHub Codespaces don't have system Chrome/Chromium installed. The `browser_use` tool's built-in browser fails to launch. Playwright installs its own Chromium to `~/.cache/ms-playwright/chromium-*/chrome-linux64/chrome` — we can drive it via CDP on port 9222.

## Quick Start

```bash
# 1. Install the Python dependency (once)
pip install -r ~/.hermes/skills/codespace/cdp-browser-testing/requirements.txt

# 2. Launch CDP Chrome (idempotent)
source ~/.hermes/skills/codespace/cdp-browser-testing/scripts/launch-chrome-cdp.sh

# 3. Use the Python CDP client
python3 -c "
import asyncio
from cdp_client import CDPClient

async def main():
    async with CDPClient() as cdp:
        await cdp.navigate('http://127.0.0.1:4387/session/xxx')
        await cdp.wait_for('#chatInput')
        await cdp.type_text('#chatInput', 'Hello from agent!')
        await cdp.click('#send')
        bubbles = await cdp.get_chat_bubbles()
        print(bubbles)

asyncio.run(main())
"
```

> The module is `cdp_client.py` (import as `from cdp_client import CDPClient`).
> Interaction helpers (`type_text`, `click`, `get_chat_bubbles`) are React-safe:
> they drive the page via `Runtime.evaluate` because CDP `DOM.querySelector`
> often returns no nodeId against React apps.

## Scripts

| Script | Purpose |
|--------|---------|
| `launch-chrome-cdp.sh` | Finds cached Playwright Chromium, starts headless on port 9222, prints WS URL |
| `cdp_client.py` | Async Python class: connect, new_page, navigate, wait_for, type_text, click, get_html, get_text, get_chat_bubbles, evaluate |
| `requirements.txt` | Python dep: `websockets` |

## Templates

| Template | Purpose |
|----------|---------|
| `common-operations.py` | Cookbook: navigate, type_text, click, wait_for, get_chat_bubbles, get_html, screenshot |

## References

| File | Content |
|------|---------|
| `cdp-api.md` | Quick-ref for CDP domains: Target, Page, DOM, Input, Runtime |

## Usage Patterns

### Launch Chrome (once per session)
```bash
source ~/.hermes/skills/codespace/cdp-browser-testing/scripts/launch-chrome-cdp.sh
# Sets CDP_WS_URL env var with ws://127.0.0.1:9222/devtools/browser/<uuid>
```

### Navigate and Interact
```python
from cdp_client import CDPClient

async with CDPClient() as cdp:
    await cdp.navigate(url)
    await cdp.wait_for('#chatInput')        # JS-based wait (React-safe)
    await cdp.type_text('#chatInput', 'message')
    await cdp.click('#send')
    bubbles = await cdp.get_chat_bubbles()  # lavish-axi chat turns
```

### Extract Data
```python
html = await cdp.get_html()        # full document outerHTML
html = await cdp.get_html('#artifact')  # scoped outerHTML
text = await cdp.get_text('h1')    # textContent of an element
val  = await cdp.evaluate("1 + 1") # any JS expression
```

## CDP WebSocket URL
The launcher prints the browser WebSocket URL. `CDPClient` auto-discovers it via `http://127.0.0.1:9222/json/version` and auto-attaches to the page target via `Target.setAutoAttach`.

## Troubleshooting
- **Chrome won't start**: Check `~/.cache/ms-playwright/chromium-*/chrome-linux64/chrome` exists (run `playwright install chromium` if not)
- **Port 9222 busy**: Kill existing `chrome --remote-debugging-port=9222` processes
- **Navigation hangs (no response to `Page.navigate`)**: Almost always orphaned CDP targets from a previous run piling up. Close them: `for p in $(pgrep -f remote-debugging-port=9222); do kill -9 $p; done`, then relaunch. The `CDPClient` now auto-attaches to page targets, so `navigate()` works without manual attach.
- **Element not found / empty bubbles**: CDP `DOM.querySelector` is unreliable against React. Use `wait_for()` + `type_text()` / `click()` (Runtime.evaluate based) instead. Read the chat via `get_chat_bubbles()` or `get_text()` rather than `div.bubble` CSS selectors.
- **`ModuleNotFoundError: cdp_client`**: ensure you import `cdp_client` (underscore), not `cdp-client`, and that the script dir is on `PYTHONPATH`.
- **Mermaid diagrams don't render**: The artifact must include the Mermaid CDN script. Add to your HTML:
  ```html
  <script type="module">
    import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11.15.0/dist/mermaid.esm.min.mjs";
    mermaid.initialize({ startOnLoad: false, theme: "default", securityLevel: "strict" });
    await mermaid.run({ nodes: [...document.querySelectorAll(".mermaid")] });
  </script>
  ```
  Without this, `<pre class="mermaid">` stays as raw text — the SDK's `mermaid-node.js` helpers only detect *rendered* SVGs.
- **Whiteboard editor cookie error**: The Excalidraw iframe is sandboxed without `allow-same-origin` (opaque origin). Clicking "Fullscreen" or interacting with the editor triggers `SecurityError: Failed to set 'cookie' property`. This is **by-design** — the whiteboard frame runs in an opaque origin matching the artifact iframe's trust posture. The diagram renders fine as a static, clickable flowchart; only the fullscreen editor is affected.

## Related Skills
- `codespace/github-codespace` — GitHub Codespace auth and workflow
- `codespace/persistent-knowledge` — Persistent skills/knowledge via symlinks