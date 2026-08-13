#!/usr/bin/env python3
"""
cdp_client.py — Async Python CDP client for headless browser automation in Codespaces.

Drives the cached Playwright Chromium over the Chrome DevTools Protocol (CDP) on
ws://127.0.0.1:9222. Works without system Chrome.

Key design note (learned the hard way):
  CDP `DOM.querySelector` is unreliable against React apps (returns no nodeId for
  elements that clearly exist). So the high-level interaction helpers here drive
  the page via `Runtime.evaluate` (set the value through the prototype setter and
  dispatch an input event, click via element.click()) — this is the reliable path.

Usage:
    from cdp_client import CDPClient

    async with CDPClient() as cdp:
        await cdp.navigate("http://127.0.0.1:4387/session/xxx")
        await cdp.wait_for("#chatInput")
        await cdp.type_text("#chatInput", "Hello from agent!")
        await cdp.click("#send")
        bubbles = await cdp.get_chat_bubbles()
"""

import asyncio
import json
import urllib.request
import websockets
from typing import Optional, Dict, Any


class CDPClient:
    """Async context manager for Chrome DevTools Protocol."""

    def __init__(self, ws_url: Optional[str] = None, cdp_http: str = "http://127.0.0.1:9222"):
        self.ws_url = ws_url
        self.cdp_http = cdp_http
        self.ws = None
        self._req_id = 0
        self._pending: Dict[int, asyncio.Future] = {}
        self._events: asyncio.Queue = asyncio.Queue()
        self._listener_task: Optional[asyncio.Task] = None
        # Page target bookkeeping
        self.target_id: Optional[str] = None
        self.session_id: Optional[str] = None

    async def __aenter__(self) -> "CDPClient":
        await self.connect()
        return self

    async def __aexit__(self, *args):
        await self.close()

    # ---- low-level transport ------------------------------------------------

    async def _listen(self):
        """Read all WebSocket frames. Resolve id-keyed responses; queue events."""
        try:
            async for raw in self.ws:
                d = json.loads(raw)
                if "id" in d and d["id"] in self._pending:
                    fut = self._pending.pop(d["id"])
                    if not fut.done():
                        if "error" in d:
                            fut.set_exception(RuntimeError(d["error"]))
                        else:
                            fut.set_result(d.get("result", {}))
                elif "method" in d:
                    await self._events.put(d)
                    # Auto-capture the page target's sessionId when attached.
                    if d["method"] == "Target.attachedToTarget":
                        info = d["params"].get("targetInfo", {})
                        if info.get("type") in ("page", "tab") or d["params"].get("sessionId"):
                            # Prefer a page target, but fall back to the first attach.
                            if self.session_id is None or info.get("type") in ("page", "tab"):
                                self.session_id = d["params"].get("sessionId")
                                self.target_id = info.get("targetId")
        except asyncio.CancelledError:
            pass

    async def _send(self, method: str, params: Dict = None, session_id: str = None,
                    timeout: float = 20.0) -> Any:
        self._req_id += 1
        msg = {"id": self._req_id, "method": method, "params": params or {}}
        sid = session_id or self.session_id
        if sid:
            msg["sessionId"] = sid
        fut = asyncio.get_event_loop().create_future()
        self._pending[self._req_id] = fut
        await self.ws.send(json.dumps(msg))
        return await asyncio.wait_for(fut, timeout=timeout)

    async def connect(self):
        """Connect to CDP, auto-discover WS URL if not provided."""
        if not self.ws_url:
            with urllib.request.urlopen(f"{self.cdp_http}/json/version") as resp:
                data = json.load(resp)
                self.ws_url = data["webSocketDebuggerUrl"]
        self.ws = await websockets.connect(self.ws_url, ping_interval=None)
        self._listener_task = asyncio.create_task(self._listen())

    # ---- target / navigation ------------------------------------------------

    async def new_page(self, url: str = "about:blank") -> str:
        """Create a new page target, attach, navigate to url. Returns sessionId."""
        res = await self._send("Target.createTarget", {"url": url})
        self.target_id = res["targetId"] if "targetId" in res else res.get("result", {}).get("targetId")
        # If auto-attach didn't fire, attach explicitly.
        if self.session_id is None:
            res = await self._send("Target.attachToTarget",
                                   {"targetId": self.target_id, "flatten": True})
            self.session_id = res["sessionId"] if "sessionId" in res else res.get("result", {}).get("sessionId")
        return self.session_id

    async def navigate(self, url: str, timeout: float = 30.0) -> str:
        """Navigate the current page target to url; wait for load event."""
        if self.session_id is None:
            await self.new_page()
        await self._send("Page.enable", {}, self.session_id)
        await self._send("Page.navigate", {"url": url}, self.session_id, timeout=timeout)
        # Wait (up to timeout) for the load event.
        try:
            await asyncio.wait_for(self._wait_event("Page.loadEventFired", self.session_id),
                                   timeout=timeout)
        except asyncio.TimeoutError:
            pass
        return self.session_id

    async def _wait_event(self, event: str, session_id: str = None, timeout: float = 10.0):
        while True:
            d = await asyncio.wait_for(self._events.get(), timeout=timeout)
            if d.get("method") == event and (session_id is None or d.get("sessionId") == session_id):
                return d

    async def wait_for(self, selector: str, timeout: float = 15.0) -> bool:
        """Wait until an element matching `selector` exists in the page (JS check)."""
        js = f"(() => !!document.querySelector({json.dumps(selector)}))()"
        for _ in range(int(timeout * 4)):
            try:
                if await self.evaluate(js):
                    return True
            except Exception:
                pass
            await asyncio.sleep(0.25)
        return False

    # ---- interaction (Runtime.evaluate based — reliable on React) -----------

    async def evaluate(self, expression: str) -> Any:
        """Evaluate JS in the page context; returns the JSON value.

        Note: Runtime.evaluate nests the return value as
        result.result.value (the outer result holds the RemoteObject, whose
        `result` holds the actual value). Handle both single- and double-nested.
        """
        res = await self._send("Runtime.evaluate",
                               {"expression": expression, "returnByValue": True},
                               self.session_id)
        if not isinstance(res, dict):
            return res
        # double-nested: {"result": {"type":..,"value":..}}
        if "result" in res and isinstance(res["result"], dict) and "value" in res["result"]:
            return res["result"]["value"]
        # single-nested / flat
        if "value" in res:
            return res["value"]
        return None

    async def type_text(self, selector: str, text: str) -> None:
        """Type `text` into the element matched by `selector` (React-safe)."""
        await self.wait_for(selector)
        js = f"""(() => {{
          const el = document.querySelector({json.dumps(selector)});
          if (!el) return 'no-element';
          let proto = el;
          while (proto && !(Object.getOwnPropertyDescriptor(proto, 'value'))) proto = Object.getPrototypeOf(proto);
          const setter = proto ? Object.getOwnPropertyDescriptor(proto, 'value').set : null;
          if (setter) {{ setter.call(el, {json.dumps(text)}); }}
          else {{ el.value = {json.dumps(text)}; }}
          el.dispatchEvent(new Event('input', {{bubbles: true}}));
          el.dispatchEvent(new Event('change', {{bubbles: true}}));
          return 'ok';
        }})()"""
        return await self.evaluate(js)

    async def click(self, selector: str) -> None:
        """Click the element matched by `selector` via element.click()."""
        await self.wait_for(selector)
        js = f"""(() => {{
          const el = document.querySelector({json.dumps(selector)});
          if (!el) return 'no-element';
          el.click();
          return 'clicked';
        }})()"""
        return await self.evaluate(js)

    async def get_html(self, selector: str = None) -> str:
        """Get outerHTML of an element (or full document)."""
        if selector:
            js = f"document.querySelector({json.dumps(selector)})?.outerHTML || ''"
        else:
            js = "document.documentElement.outerHTML"
        return await self.evaluate(js) or ""

    async def get_text(self, selector: str = None) -> str:
        """Get textContent of an element (or full body)."""
        js = (f"document.querySelector({json.dumps(selector)})?.innerText || ''"
              if selector else "document.body.innerText")
        return await self.evaluate(js) or ""

    async def get_chat_bubbles(self) -> list:
        """Return list of {{role: 'YOU'|'AGENT', text}} from lavish-axi chat."""
        js = r"""(() => {
          const els = [...document.querySelectorAll('[class*="bubble"]')];
          return els.map(b => ({
            role: /user/.test(b.className) ? 'YOU' : 'AGENT',
            text: b.innerText.replace(/^(YOU|AGENT)\s*/, '')
          }));
        })()"""
        return await self.evaluate(js) or []

    # ---- teardown -----------------------------------------------------------

    async def close_target(self):
        if self.target_id:
            try:
                await self._send("Target.closeTarget", {"targetId": self.target_id}, timeout=5)
            except Exception:
                pass

    async def close(self):
        if self._listener_task:
            self._listener_task.cancel()
            try:
                await self._listener_task
            except asyncio.CancelledError:
                pass
        if self.ws:
            await self.ws.close()
