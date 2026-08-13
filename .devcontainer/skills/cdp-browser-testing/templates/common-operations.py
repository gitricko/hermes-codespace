#!/usr/bin/env python3
"""
common-operations.py — Cookbook of common CDP operations
Copy-paste these patterns into your test scripts
"""

import asyncio
from cdp_client import CDPClient


async def example_basic_navigation():
    """Navigate and extract page title"""
    async with CDPClient() as cdp:
        await cdp.navigate("https://example.com")
        title = await cdp.evaluate("document.title")
        print(f"Title: {title}")


async def example_form_interaction():
    """Fill form and submit"""
    async with CDPClient() as cdp:
        await cdp.navigate("http://127.0.0.1:4387/session/xxx")
        
        # Wait for chat input
        await cdp.wait_for_selector("#chatInput")
        
        # Type message
        await cdp.type("#chatInput", "Hello from automated test!")
        
        # Click send
        await cdp.click("#send")
        
        # Wait a bit for response
        await asyncio.sleep(2)
        
        # Get chat log
        html = await cdp.get_html("#chatLog")
        print(html)


async def example_wait_and_extract():
    """Wait for dynamic content and extract"""
    async with CDPClient() as cdp:
        await cdp.navigate("http://127.0.0.1:4387/session/xxx")
        
        # Wait for specific element
        await cdp.wait_for_selector(".bubble.agent:last-child")
        
        # Extract text
        text = await cdp.extract_text(".bubble.agent:last-child")
        print(f"Latest agent reply: {text}")


async def example_multiple_interactions():
    """Full interaction loop: send message, wait for reply, verify"""
    async with CDPClient() as cdp:
        await cdp.navigate("http://127.0.0.1:4387/session/xxx")
        
        # Send first message
        await cdp.type("#chatInput", "Test message 1")
        await cdp.click("#send")
        await asyncio.sleep(3)
        
        # Send second message
        await cdp.type("#chatInput", "Test message 2")
        await cdp.click("#send")
        await asyncio.sleep(3)
        
        # Get full chat log
        html = await cdp.get_html("#chatLog")
        
        # Verify both messages present
        assert "Test message 1" in html
        assert "Test message 2" in html
        print("Both messages verified in chat log")


async def example_artifact_testing():
    """Test lavish-axi artifact rendering"""
    async with CDPClient() as cdp:
        await cdp.navigate("http://127.0.0.1:4387/session/xxx")
        
        # Check editor chrome loaded
        await cdp.wait_for_selector(".editor-chrome, .conversation-panel, #chatInput")
        
        # Check artifact iframe
        await cdp.wait_for_selector("iframe[src*='artifact']")
        
        # Get artifact content
        iframe_html = await cdp.get_html("iframe[src*='artifact']")
        print("Artifact iframe found")


async def example_screenshot():
    """Take screenshot via CDP"""
    async with CDPClient() as cdp:
        await cdp.navigate("http://127.0.0.1:4387/session/xxx")
        await cdp.wait_for_selector("#chatInput")
        
        # Screenshot via CDP
        result = await cdp._send("Page.captureScreenshot", {"format": "png", "fromSurface": True})
        import base64
        img_data = base64.b64decode(result.get("data", ""))
        with open("/tmp/screenshot.png", "wb") as f:
            f.write(img_data)
        print("Screenshot saved to /tmp/screenshot.png")


async def example_console_logs():
    """Capture console logs"""
    async with CDPClient() as cdp:
        logs = []
        
        # Enable Runtime domain for console
        await cdp._send("Runtime.enable")
        
        # Set up console listener (simplified)
        await cdp.navigate("http://127.0.0.1:4387/session/xxx")
        
        # Get console messages
        result = await cdp.evaluate("""
            (() => {
                const logs = [];
                const original = console.log;
                console.log = (...args) => { logs.push(args.join(' ')); original.apply(console, args); };
                return logs;
            })()
        """)
        print(f"Console logs: {result}")


if __name__ == "__main__":
    # Run examples
    asyncio.run(example_basic_navigation())
    # asyncio.run(example_form_interaction())
    # asyncio.run(example_wait_and_extract())
    # asyncio.run(example_multiple_interactions())
    # asyncio.run(example_artifact_testing())
    # asyncio.run(example_screenshot())
    # asyncio.run(example_console_logs())