#!/usr/bin/env python3
"""
common-operations.py — Cookbook of common CDP operations for the
cdp-browser-testing skill. Copy-paste these patterns into your test scripts.

NOTE: the high-level helpers (type_text / click / get_chat_bubbles) drive the
page via Runtime.evaluate, which is reliable against React apps (unlike
CDP DOM.querySelector, which often returns no nodeId). Use those helpers.
"""

import asyncio
from cdp_client import CDPClient


async def example_basic_navigation():
    """Navigate and extract page title."""
    async with CDPClient() as cdp:
        await cdp.navigate("https://example.com")
        title = await cdp.evaluate("document.title")
        print(f"Title: {title}")


async def example_form_interaction():
    """Fill form and submit (lavish-axi chat composer)."""
    async with CDPClient() as cdp:
        await cdp.navigate("http://127.0.0.1:4387/session/xxx")
        await cdp.wait_for("#chatInput")
        await cdp.type_text("#chatInput", "Hello from automated test!")
        await cdp.click("#send")
        await asyncio.sleep(2)
        html = await cdp.get_html("#chatLog")
        print(html)


async def example_wait_and_extract():
    """Wait for an agent reply bubble and extract its text."""
    async with CDPClient() as cdp:
        await cdp.navigate("http://127.0.0.1:4387/session/xxx")
        # get_chat_bubbles waits via JS polling internally is not built-in;
        # poll until an AGENT bubble appears:
        for _ in range(20):
            bubbles = await cdp.get_chat_bubbles()
            if any(b["role"] == "AGENT" for b in bubbles):
                break
            await asyncio.sleep(0.5)
        bubbles = await cdp.get_chat_bubbles()
        for b in bubbles:
            print(f"[{b['role']}] {b['text']}")


async def example_full_roundtrip():
    """Full interaction loop: send message, wait for reply, verify."""
    async with CDPClient() as cdp:
        await cdp.navigate("http://127.0.0.1:4387/session/xxx")
        await cdp.wait_for("#chatInput")
        await cdp.type_text("#chatInput", "Test message 1")
        await cdp.click("#send")
        await asyncio.sleep(3)
        await cdp.type_text("#chatInput", "Test message 2")
        await cdp.click("#send")
        await asyncio.sleep(3)
        bubbles = await cdp.get_chat_bubbles()
        texts = " ".join(b["text"] for b in bubbles)
        assert "Test message 1" in texts
        assert "Test message 2" in texts
        print("Both messages verified in chat log")


async def example_artifact_testing():
    """Test lavish-axi artifact rendering."""
    async with CDPClient() as cdp:
        await cdp.navigate("http://127.0.0.1:4387/session/xxx")
        await cdp.wait_for("#chatInput")
        # The artifact iframe is created by the app; read its src once present.
        src = await cdp.evaluate(
            "document.querySelector('iframe[src*=artifact]')?.src || ''")
        print("Artifact iframe:", src or "not yet present")


async def example_screenshot():
    """Take a screenshot via CDP."""
    async with CDPClient() as cdp:
        await cdp.navigate("http://127.0.0.1:4387/session/xxx")
        await cdp.wait_for("#chatInput")
        result = await cdp._send("Page.captureScreenshot",
                                 {"format": "png", "fromSurface": True},
                                 cdp.session_id)
        import base64
        img_data = base64.b64decode(result.get("data", ""))
        with open("/tmp/screenshot.png", "wb") as f:
            f.write(img_data)
        print("Screenshot saved to /tmp/screenshot.png")


if __name__ == "__main__":
    asyncio.run(example_basic_navigation())
    # asyncio.run(example_form_interaction())
    # asyncio.run(example_wait_and_extract())
    # asyncio.run(example_full_roundtrip())
    # asyncio.run(example_artifact_testing())
    # asyncio.run(example_screenshot())
