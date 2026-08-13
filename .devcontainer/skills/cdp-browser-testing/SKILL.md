---
name: cdp-browser-testing
description: Headless browser automation in Codespaces w/ Playwright CDP.
trigger: Use when you need headless browser automation in Codespaces without system Chrome.
category: codespace
version: 1.0.0
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
# Launch CDP Chrome (idempotent)
source ~/.hermes/skills/codespace/cdp-browser-testing/scripts/launch-chrome-cdp.sh

# Use Python CDP client
python3 -c "
import asyncio
from cdp_client import CDPClient

async def main():
    async with CDPClient() as cdp:
        await cdp.navigate('http://127.0.0.1:4387/session/xxx')
        await cdp.type('#chatInput', 'Hello from agent!')
        await cdp.click('#send')
        html = await cdp.get_html('#chatLog')
        print(html)

asyncio.run(main())
"
```

## Scripts

| Script | Purpose |
|--------|---------|
| `launch-chrome-cdp.sh` | Finds cached Playwright Chromium, starts headless on port 9222, prints WS URL |
| `cdp-client.py` | Async Python class: connect, navigate, click, type, get_html, wait_for_selector |

## Templates

| Template | Purpose |
|----------|---------|
| `common-operations.py` | Cookbook: click, type, wait_for_selector, get_html, screenshot, extract_text |

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
    await cdp.wait_for_selector('#chatInput')
    await cdp.type('#chatInput', 'message')
    await cdp.click('#send')
    html = await cdp.get_html('#chatLog')
```

### Extract Data
```python
html = await cdp.get_html()  # full page
html = await cdp.get_html('#artifact')  # scoped
text = await cdp.extract_text('h1')
```

## CDP WebSocket URL
The launcher prints the browser WebSocket URL. `CDPClient` auto-discovers it via `http://127.0.0.1:9222/json/version`.

## Troubleshooting

- **Chrome won't start**: Check `~/.cache/ms-playwright/chromium-*/chrome-linux64/chrome` exists (run `playwright install chromium` if not)
- **Port 9222 busy**: Kill existing `chrome --remote-debugging-port=9222` processes
- **Navigation hangs**: Increase wait timeout, check for JS errors via `cdp.evaluate('console.error')`
- **Element not found**: Wait for `Page.loadEventFired` + `DOMContentLoaded`, then `wait_for_selector`

## Related Skills
- `codespace/github-codespace` — GitHub Codespace auth and workflow
- `codespace/persistent-knowledge` — Persistent skills/knowledge via symlinks