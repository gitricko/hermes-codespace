#!/usr/bin/env python3
"""
cdp-client.py — Async Python CDP client for browser automation
Usage: from cdp_client import CDPClient
"""

import asyncio
import json
import websockets
from typing import Optional, Dict, Any, List


class CDPClient:
    """Async context manager for Chrome DevTools Protocol"""
    
    def __init__(self, ws_url: Optional[str] = None, cdp_http: str = "http://127.0.0.1:9222"):
        self.ws_url = ws_url
        self.cdp_http = cdp_http
        self.ws: Optional[websockets.WebSocketClientProtocol] = None
        self.session_id: Optional[str] = None
        self._req_id = 0
        self._pending: Dict[int, asyncio.Future] = {}
        self._listener_task: Optional[asyncio.Task] = None
    
    async def __aenter__(self) -> "CDPClient":
        await self.connect()
        return self
    
    async def __aexit__(self, *args):
        await self.close()
    
    async def connect(self):
        """Connect to CDP, auto-discover WS URL if not provided"""
        if not self.ws_url:
            import urllib.request
            with urllib.request.urlopen(f"{self.cdp_http}/json/version") as resp:
                data = json.load(resp)
                self.ws_url = data["webSocketDebuggerUrl"]
        
        self.ws = await websockets.connect(self.ws_url)
        self._listener_task = asyncio.create_task(self._listen())
        
        # Enable domains
        await self._send("Target.setDiscoverTargets", {"discover": True})
        await self._send("Target.setAutoAttach", {"autoAttach": True, "flatten": True, "waitForDebuggerOnStart": False})
    
    async def _listen(self):
        try:
            async for msg in self.ws:
                data = json.loads(msg)
                if "id" in data and data["id"] in self._pending:
                    fut = self._pending.pop(data["id"])
                    if not fut.done():
                        if "error" in data:
                            fut.set_exception(Exception(data["error"]))
                        else:
                            fut.set_result(data.get("result", {}))
                elif "method" in data and data["method"] == "Target.targetCreated":
                    # Auto-attach to new targets
                    target_id = data["params"]["targetInfo"]["targetId"]
                    await self._send("Target.attachToTarget", {"targetId": target_id, "flatten": True})
        except asyncio.CancelledError:
            pass
    
    async def _send(self, method: str, params: Dict = None, session_id: str = None) -> Any:
        self._req_id += 1
        msg = {"id": self._req_id, "method": method, "params": params or {}}
        if session_id or self.session_id:
            msg["sessionId"] = session_id or self.session_id
        
        fut = asyncio.get_event_loop().create_future()
        self._pending[self._req_id] = fut
        await self.ws.send(json.dumps(msg))
        return await fut
    
    # High-level API
    
    async def navigate(self, url: str, timeout: float = 30.0) -> str:
        """Navigate to URL, wait for load"""
        result = await self._send("Page.navigate", {"url": url})
        frame_id = result.get("frameId")
        
        # Wait for load event
        try:
            await asyncio.wait_for(self._wait_for_event("Page.loadEventFired"), timeout=timeout)
        except asyncio.TimeoutError:
            pass
        return frame_id or ""
    
    async def _wait_for_event(self, event: str, timeout: float = 10.0) -> Dict:
        # Simplified: in real use, you'd register event handlers
        await asyncio.sleep(1)  # Basic wait
        return {}
    
    async def wait_for_selector(self, selector: str, timeout: float = 10.0) -> str:
        """Wait for element to exist, return nodeId"""
        await self._send("DOM.enable")
        await self._send("DOM.getDocument", {"depth": -1})
        
        for _ in range(int(timeout * 2)):
            result = await self._send("DOM.querySelector", {"selector": selector})
            node_id = result.get("nodeId")
            if node_id:
                return str(node_id)
            await asyncio.sleep(0.5)
        raise TimeoutError(f"Selector not found: {selector}")
    
    async def type(self, selector: str, text: str) -> None:
        """Focus element and type text"""
        node_id = await self.wait_for_selector(selector)
        await self._send("DOM.focus", {"nodeId": int(node_id)})
        await asyncio.sleep(0.2)
        await self._send("Input.insertText", {"text": text})
        await asyncio.sleep(0.2)
    
    async def click(self, selector: str) -> None:
        """Click element via box model"""
        node_id = await self.wait_for_selector(selector)
        box = await self._send("DOM.getBoxModel", {"nodeId": int(node_id)})
        content = box.get("model", {}).get("content", [])
        if len(content) >= 4:
            x = (content[0] + content[2]) / 2
            y = (content[1] + content[5]) / 2
            await self._send("Input.dispatchMouseEvent", {
                "type": "mousePressed", "x": x, "y": y, "button": "left", "clickCount": 1
            })
            await asyncio.sleep(0.05)
            await self._send("Input.dispatchMouseEvent", {
                "type": "mouseReleased", "x": x, "y": y, "button": "left", "clickCount": 1
            })
    
    async def get_html(self, selector: str = None) -> str:
        """Get outerHTML of element or full document"""
        await self._send("DOM.enable")
        doc = await self._send("DOM.getDocument", {"depth": -1})
        root_id = doc.get("root", {}).get("nodeId")
        
        if selector:
            result = await self._send("DOM.querySelector", {"nodeId": root_id, "selector": selector})
            node_id = result.get("nodeId")
        else:
            node_id = root_id
        
        result = await self._send("DOM.getOuterHTML", {"nodeId": node_id})
        return result.get("outerHTML", "")
    
    async def extract_text(self, selector: str) -> str:
        """Get textContent of element"""
        html = await self.get_html(selector)
        # Simple extraction - in production use DOM.getTextContent
        import re
        return re.sub(r"<[^>]+>", "", html).strip()
    
    async def evaluate(self, expression: str) -> Any:
        """Evaluate JS in page context"""
        result = await self._send("Runtime.evaluate", {"expression": expression, "returnByValue": True})
        return result.get("result", {}).get("value")
    
    async def close(self):
        if self._listener_task:
            self._listener_task.cancel()
            try:
                await self._listener_task
            except asyncio.CancelledError:
                pass
        if self.ws:
            await self.ws.close()