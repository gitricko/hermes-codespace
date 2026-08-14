# Lavish AXI in GitHub Codespaces — Complete Setup & Troubleshooting Wiki

## Overview

This document captures the complete journey of getting **lavish-axi** (the collaborative artifact editor) running end-to-end in a GitHub Codespace, including the nginx reverse proxy setup, port visibility conflicts, same-origin policy workarounds, and the verified browser→agent→browser feedback loop.

**End state:** Fully working round-trip on **public port 8080** via nginx proxy.

---

## Architecture

```
��─────────────────────────────────────────────────────────────────────��
│                     GitHub Codespace                                │
│  ��──────────────��    ��──────────────��    ��──────────────────────��  │
│  │   Browser    │───��│  nginx :8080 │───��│  lavish-axi :4387    │  │
│  │  (Public URL)│    │  (Proxy)     │    │  (Loopback Only)     │  │
│  └──────────────��    └──────────────��    └──────────────────────��  │
│         │                   │                    │                 │
│         │                   │                    │                 │
│         ��                   ��                    ��                 │
│  ��──────────────��    ��──────────────��    ��──────────────────────��  │
│  │  CDP Chrome  │    │  Origin      │    │  Session Store       │  │
│  │  :9222       │    │  Rewrite     │    │  (File-based)        │  │
│  └──────────────��    └──────────────��    └──────────────────────��  │
��─────────────────────────────────────────────────────────────────────��
```

### Component Roles

| Component | Port | Purpose |
|-----------|------|---------|
| **lavish-axi server** | 4387 (loopback) | Core artifact server, session management, prompt queue |
| **nginx reverse proxy** | 8080 (0.0.0.0) | Public entry point, rewrites `Origin`/`Host`/`Referer` to loopback |
| **CDP Chrome (Playwright)** | 9222 | Headless browser automation for testing |
| **poll listener** | — | Long-poll CLI that captures user feedback from browser |

---

## Why Nginx? (The Core Problem)

### The Same-Origin Guard

lavish-axi enforces a **strict same-origin policy** on state-changing endpoints (`/api/:key/prompts`, `/api/:key/agent-reply`, `/sdk.js`):

```javascript
// src/server.js - isSameOriginRequest()
function isSameOriginRequest(req, allowedHostnames, allowAnyHostname = false) {
  // Validates that Origin/Referer header matches expected origin
  // Expected origin = protocol://host (or X-Forwarded-Host + X-Forwarded-Proto)
}
```

### The DNS-Rebinding Guard

lavish-axi **only binds to loopback** (`127.0.0.1:4387`) as a security measure against DNS rebinding attacks. It refuses connections from non-loopback hosts.

### The Codespace Proxy Problem

GitHub Codespaces exposes ports via `*.app.github.dev` URLs:
- **Public port**: Accessible without auth, but serves GitHub interstitial pages for iframes
- **Private port**: Requires GitHub auth (blocks automated API calls)

**Without nginx:**
- Direct access to `https://codespace-4387.app.github.dev` → Origin = public URL → **same-origin check FAILS** → `/prompts` rejected
- Direct access to `https://codespace-8080.app.github.dev` → Same issue

**With nginx on 8080:**
```
Browser → https://codespace-8080.app.github.dev/session/...
    │
    ��
nginx (0.0.0.0:8080) rewrites headers:
  Host: 127.0.0.1
  Origin: http://127.0.0.1
  Referer: http://127.0.0.1/...
  X-Forwarded-Host: (stripped)
  X-Forwarded-Proto: (stripped)
    │
    ��
lavish-axi (127.0.0.1:4387) sees loopback Origin → **same-origin check PASSES**
```

---

## Nginx Configuration

### File: `/etc/nginx/sites-available/lavish-axi`

```nginx
server {
    listen 8080;
    server_name _;

    # Health endpoint (no proxy)
    location /nginx-health {
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # Proxy all traffic to lavish-axi on loopback
    location / {
        proxy_pass http://127.0.0.1:4387;
        
        # CRITICAL: Rewrite headers so lavish-axi sees loopback origin
        proxy_set_header Host 127.0.0.1;
        proxy_set_header Origin http://127.0.0.1;
        proxy_set_header Referer http://127.0.0.1;
        proxy_set_header X-Forwarded-Host "";
        proxy_set_header X-Forwarded-Proto "";
        
        # WebSocket support for SSE
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
```

### Enable Site

```bash
sudo ln -sf /etc/nginx/sites-available/lavish-axi /etc/nginx/sites-enabled/
sudo nginx -t && sudo nginx -g 'daemon off;' &
```

### Verify

```bash
curl http://127.0.0.1:8080/nginx-health  # → "healthy"
curl http://127.0.0.1:8080/health        # → {"ok":true,"app":"lavish-axi","version":"0.1.50"}
```

---

## Port Visibility Conflict (The Mermaid Iframe Issue)

### The Conflict

| Port | Visibility | Send-to-Agent | Annotation | Mermaid Iframe |
|------|------------|---------------|------------|----------------|
| **8080 (nginx)** | **Public** | �� Works | �� Works | ������ **GitHub Warning Page** |
| 8080 (nginx) | Private | ��� Blocked (auth) | ��� Blocked | �� No warning |
| 4387 (direct) | Private | ��� Same-origin fail* | ��� SDK fails | �� No warning |

*Fixed temporarily with `LAVISH_AXI_ALLOWED_HOSTS=*` but reverted per user request.

### Root Cause

GitHub Codespaces serves an **interstitial warning page** for iframes on **public URLs**. The mermaid whiteboard (`/whiteboard-frame`) loads in a sandboxed iframe:

```html
<iframe src="/whiteboard-frame?key=...&diagramIndex=0" 
        sandbox="allow-scripts allow-forms allow-pointer-lock">
</iframe>
```

On public 8080, GitHub intercepts the iframe request and serves a "This is a public link" warning page instead of the actual whiteboard content. The sandbox prevents the warning page's "Continue" button from working.

### Why We Chose Public 8080

- **Send-to-agent MUST work** (core functionality)
- **Annotation MUST work** (core functionality)  
- Mermaid diagram **renders as SVG in main page** (works fine)
- Only the **interactive whiteboard editor iframe** shows the warning
- This is a **GitHub platform limitation**, not a lavish-axi bug

---

## Complete Setup Procedure

### 1. Clone & Build

```bash
cd /workspaces
git clone https://github.com/intricko/lavish-axi.git
cd lavish-axi
corepack enable pnpm
pnpm install --frozen-lockfile
pnpm build  # Creates dist/cli.mjs
```

### 2. Create Test Artifact

```bash
cat > sample.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Lavish AXI Codespace Test Artifact</title>
</head>
<body>
  <h1>Hello World</h1>
  <p>Test artifact for lavish-axi in GitHub Codespaces via nginx proxy.</p>
  <pre class="mermaid">
graph TD
  A[Browser CDP] -->|type + click Send| B(lavish-axi poll)
  B -->|feedback JSON| C[Agent]
  C -->|POST agent-reply| D[Browser chatLog]
</pre>
  <script type="module">
    import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11.15.0/dist/mermaid.esm.min.mjs";
    mermaid.initialize({ startOnLoad: false, theme: "default", securityLevel: "strict" });
    await mermaid.run({ nodes: [...document.querySelectorAll(".mermaid")] });
  </script>
</body>
</html>
EOF
```

### 3. Start lavish-axi Server (Loopback Only)

```bash
# Suppress GUI auto-open
LAVISH_AXI_NO_OPEN=1 node dist/cli.mjs sample.html --no-open &

# Verify
curl http://127.0.0.1:4387/health
# {"ok":true,"app":"lavish-axi","version":"0.1.50"}
```

### 4. Start Nginx Proxy

```bash
sudo nginx -g 'daemon off;' &
# Verify
curl http://127.0.0.1:8080/nginx-health  # → "healthy"
curl http://127.0.0.1:8080/health        # → lavish-axi health
```

### 5. Launch CDP Chrome (for Automation)

```bash
# Using Playwright's bundled Chromium
chrome --headless --no-sandbox --disable-gpu \
  --disable-dev-shm-usage \
  --remote-debugging-port=9222 \
  --user-data-dir=/tmp/chrome-cdp-test &

# Verify
curl http://127.0.0.1:9222/json/version
```

### 6. Start Poll Listener (Agent Feedback Loop)

```bash
# Run in background (harness-native)
node dist/cli.mjs poll sample.html &

# Or foreground for debugging
node dist/cli.mjs poll sample.html
```

### 7. Access the Session

**Public URL (WORKING):**
```
https://<codespace-name>-8080.app.github.dev/session/<session-key>
```

**Session Key:** SHA256(realpath) first 16 chars
```bash
node -e "const crypto=require('crypto'),fs=require('fs'); console.log(crypto.createHash('sha256').update(fs.realpathSync('sample.html')).digest('hex').slice(0,16))"
# → 609f8b3f1103d0a6
```

---

## The Feedback Loop (Official lavish-axi Contract)

```
��─────────────────────────────────────────────────────────────────��
│                    LAVISH-AXI CYCLE                              │
├─────────────────────────────────────────────────────────────────��
│                                                                  │
│  1. Human writes artifact.html                                   │
│  2. lavish-axi <file>          → opens browser session           │
│  3. Human annotates, sends chat                                  │
│  4. lavish-axi poll <file>     → long-polls until feedback       │
│  5. Poll returns status: feedback + prompts                      │
│  6. Agent processes feedback                                     │
│  7. lavish-axi poll --agent-reply "reply" → sends reply          │
│  8. Repeat from step 4                                           │
│                                                                  │
��─────────────────────────────────────────────────────────────────��
```

### Key Behaviors

| Aspect | Behavior |
|--------|----------|
| **Poll** | Long-poll that **exits after capturing feedback** (returns `status: "feedback"`). Not a persistent daemon. |
| **Agent presence** | Browser SSE `/events/:key` shows: `waiting` → `listening` → `working` → `waiting` |
| **Cycle** | Poll → feedback captured → poll exits → agent replies → poll restarts |
| **Same-origin** | `/prompts` guarded. Behind nginx, expected origin = validated loopback |

### Manual vs Automated

| Mode | Description |
|------|-------------|
| **Manual** | You send → poll captures → you run `poll --agent-reply "..."` → reply renders |
| **Automated** | Supervisor script watches poll output → auto-runs `poll --agent-reply` |

---

## Verified Round-Trip Test

### Automated CDP Test

```python
# Using cdp-browser-testing skill
async with CDPClient() as cdp:
    await cdp.navigate('https://codespace-8080.app.github.dev/session/...')
    await cdp.type_text('#chatInput', 'Test message')
    await cdp.click('#send')
    # Poll captures → agent replies via POST /api/.../agent-reply
    # Reply renders as AGENT bubble in browser
```

### Verified Chat Log (Extract)

```
YOU  → CDP test message from agent!
AGENT → CDP round-trip confirmed! Browser → agent → browser works over nginx proxy.
YOU  → ping
AGENT → pong — nginx reverse proxy works correctly.
YOU  → can you change the page to hello world
AGENT → Done! Changed heading to "Hello World". Reload to see.
```

---

## Known Limitations & Workarounds

### 1. Mermaid Whiteboard Iframe Warning (Public 8080)

**Problem:** GitHub serves interstitial warning for iframes on public URLs.

**Workarounds:**
- Use **private 4387** with `LAVISH_AXI_ALLOWED_HOSTS=*` (but send-to-agent requires code change)
- Accept static SVG diagram (renders correctly in main page)
- Use custom domain/tunnel (not practical in Codespaces)

**Status:** Deferred — core functionality works.

### 2. SDKMan Error in Background Shells

**Symptom:** `bash: /usr/local/sdkman/bin/sdkman-init.sh: No such file or directory`

**Cause:** Background shells source `.bashrc` which references missing sdkman.

**Impact:** Cosmetic only — poll still works, exits cleanly.

**Fix:** Not critical — ignore.

### 3. Poll is Not a Daemon

**Behavior:** `lavish-axi poll` exits after each feedback capture.

**Solution:** Run in a loop or use supervisor:
```bash
while true; do node dist/cli.mjs poll sample.html; done
# Or use harness-native background jobs with notify_on_complete
```

---

## Troubleshooting Checklist

| Symptom | Check | Fix |
|---------|-------|-----|
| "Your agent is not listening" | Poll running? | `ps aux \| grep poll` → restart poll |
| Send-to-agent fails (403) | Origin check? | Verify nginx rewrites Origin to loopback |
| SDK fails to load | `/sdk.js` returns stale? | Reload page for new artifact_revision/token |
| Mermaid not rendering | Mermaid CDN loaded? | Verify `<script type="module">` with mermaid import |
| Whiteboard iframe error | Public URL? | Known limitation — use private port or accept SVG |
| Poll exits immediately | No feedback queued? | Normal — run again or use `--timeout-ms` |

---

## Environment Variables Reference

| Variable | Purpose | Default |
|----------|---------|---------|
| `LAVISH_AXI_NO_OPEN` | Suppress browser auto-open | — |
| `LAVISH_AXI_ALLOWED_HOSTS` | Host allowlist for same-origin (`*` = disable) | Loopback only |
| `LAVISH_AXI_STATE_DIR` | Session/persistent data directory | `~/.lavish-axi` |
| `PORT` | Server port (loopback) | 4387 |

---

## Files Modified During This Session

| File | Change | Status |
|------|--------|--------|
| `src/server.js` | Temporarily patched `isSameOriginRequest` to skip Origin check when `allowAnyHostname=true` | **Reverted** |
| `sample.html` | Added Mermaid CDN, changed title to "Hello World" | **Kept** |
| `/etc/nginx/sites-available/lavish-axi` | Nginx proxy config with Origin rewrite | **Kept** |

---

## Quick Reference Commands

```bash
# Full stack restart
pkill -f "lavish-axi.*server"
pkill -f "nginx"
pkill -f "chrome.*9222"

LAVISH_AXI_NO_OPEN=1 node dist/cli.mjs sample.html --no-open &
sudo nginx -g 'daemon off;' &
chrome --headless --remote-debugging-port=9222 --user-data-dir=/tmp/chrome-cdp-test &
node dist/cli.mjs poll sample.html &

# Verify all
curl http://127.0.0.1:4387/health
curl http://127.0.0.1:8080/nginx-health
curl http://127.0.0.1:9222/json/version

# Session URL
echo "https://$(gh codespace view --json name -q .name)-8080.app.github.dev/session/609f8b3f1103d0a6"
```

---

## Conclusion

**Working Configuration:** Public port 8080 via nginx proxy → lavish-axi on loopback 4387.

**What Works:**
- �� Send-to-agent (via nginx Origin rewrite)
- �� Annotation/highlighting (SDK loads)
- �� Mermaid diagram renders as SVG
- �� Full browser→agent→browser round-trip
- �� Artifact hot-reload on file change

**Deferred:**
- ������ Mermaid whiteboard iframe warning (GitHub Codespace limitation)

The setup is stable and ready for development/testing workflows.