# CDP API Quick Reference

Domains used in this skill:

## Target
- `Target.getTargets` — List all targets (pages, workers, etc.)
- `Target.attachToTarget` — Attach to a target for debugging
- `Target.setDiscoverTargets` — Enable target discovery
- `Target.setAutoAttach` — Auto-attach to new targets

## Page
- `Page.enable` — Enable Page domain
- `Page.navigate` — Navigate to URL
- `Page.loadEventFired` — Event: page load complete
- `Page.domContentEventFired` — Event: DOMContentLoaded
- `Page.captureScreenshot` — Take screenshot
- `Page.getFrameTree` — Get frame hierarchy

## DOM
- `DOM.enable` — Enable DOM domain
- `DOM.getDocument` — Get root document node
- `DOM.querySelector` — Find element by CSS selector
- `DOM.getBoxModel` — Get element geometry (for clicking)
- `DOM.getOuterHTML` — Get element's outerHTML
- `DOM.focus` — Focus element
- `DOM.getTextContent` — Get textContent (if available)

## Input
- `Input.insertText` — Type text into focused element
- `Input.dispatchMouseEvent` — Mouse events (click, move, etc.)
- `Input.dispatchKeyEvent` — Keyboard events

## Runtime
- `Runtime.enable` — Enable Runtime domain
- `Runtime.evaluate` — Evaluate JavaScript in page context
- `Runtime.consoleAPICalled` — Event: console.log/error/etc.

---

## Common Patterns

### Get WebSocket URL
```bash
curl -s http://127.0.0.1:9222/json/version | jq -r .webSocketDebuggerUrl
```

### Attach to page target
```json
{"id": 1, "method": "Target.attachToTarget", "params": {"targetId": "<targetId>", "flatten": true}}
```

### Navigate and wait
```json
{"id": 1, "method": "Page.navigate", "params": {"url": "http://localhost:4387/session/xxx"}}
```
Then wait for `Page.loadEventFired` event.

### Click element
1. `DOM.querySelector` with selector → get `nodeId`
2. `DOM.getBoxModel` with `nodeId` → get `content` array
3. Calculate center: `x = (content[0] + content[2]) / 2`, `y = (content[1] + content[5]) / 2`
4. `Input.dispatchMouseEvent` with `mousePressed` at (x,y)
5. `Input.dispatchMouseEvent` with `mouseReleased` at (x,y)

> NOTE: `DOM.querySelector` is unreliable against React apps (returns no nodeId for
> elements that clearly exist). The `cdp_client.py` helpers `type_text()` and
> `click()` drive the page via `Runtime.evaluate` instead — prefer those.

### Type text (React-safe — preferred)
```js
(() => {
  const el = document.querySelector("#chatInput");
  const setter = Object.getOwnPropertyDescriptor(
    window.HTMLTextAreaElement.prototype, "value").set;
  setter.call(el, "your text");
  el.dispatchEvent(new Event("input", {bubbles: true}));
  el.dispatchEvent(new Event("change", {bubbles: true}));
})()
```

### Get element HTML
1. `DOM.getDocument` → `root.nodeId`
2. `DOM.querySelector` with `nodeId` and selector → `nodeId`
3. `DOM.getOuterHTML` with `nodeId` → `outerHTML`