# Artifact Load Tokens — Verification Pitfalls

## The Problem

Lavish-AXI generates a unique `loadToken` for each artifact load attempt. This token:
- Is embedded in the session page (`initialArtifactLoadToken`)
- Is required to fetch the artifact via `/artifact/<key>/index.html?loadToken=...`
- **Expires quickly** (seconds) after the session page loads

## What Fails

```bash
# This DOES NOT WORK — token is stale by the time you curl
TOKEN=$(curl -s "http://127.0.0.1:4387/session/KEY" | grep -o 'initialArtifactLoadToken":"[^"]*' | cut -d'"' -f4)
curl "http://127.0.0.1:4387/artifact/KEY/index.html?loadToken=$TOKEN"
# → "Artifact load expired"
```

## What Works

The artifact renders **inside the noVNC iframe** when Chrome loads the session page. The token is validated by the iframe's `src` URL.

### Correct Verification

```bash
# 1. Health endpoint (always works)
curl -s http://127.0.0.1:4387/health
# → {"ok":true,...}

# 2. noVNC page (served by websockify)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:6080/vnc.html
# → 200

# 3. Session page (returns 200, contains iframe with artifact src)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:4387/session/KEY
# → 200
```

## Why This Matters

- **Don't** verify by curling the artifact endpoint directly
- **Do** verify the stack: health + noVNC + session page all return 200
- The artifact loads correctly in the user's browser via noVNC iframe

## Debugging Token Issues

If the artifact doesn't appear in noVNC:
1. Check Chrome is running on :99 (`pgrep -f "chrome.*chrome-gui"`)
2. Check x11vnc is exporting :99 (`pgrep -f "x11vnc.*:99"`)
3. Check websockify is bridging :5900 → :6080 (`pgrep -f "websockify.*6080"`)
4. Open the noVNC URL in a real browser — the iframe loads the artifact there