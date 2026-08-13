#!/usr/bin/env bash
# launch-chrome-cdp.sh — Idempotent launcher for Playwright Chromium via CDP on port 9222
# Usage: source this script to set CDP_WS_URL in your shell

set -euo pipefail

# Find Playwright's cached Chromium
CHROME_PATH=$(find ~/.cache/ms-playwright -name "chrome" -path "*/chrome-linux64/chrome" 2>/dev/null | head -1)

if [[ -z "$CHROME_PATH" ]]; then
    echo "ERROR: Playwright Chromium not found. Run: playwright install chromium" >&2
    exit 1
fi

if [[ ! -x "$CHROME_PATH" ]]; then
    echo "ERROR: Chrome binary not executable: $CHROME_PATH" >&2
    exit 1
fi

# Check if already running on port 9222
if curl -sf http://127.0.0.1:9222/json/version >/dev/null 2>&1; then
    # Extract WS URL from existing instance
    CDP_WS_URL=$(curl -s http://127.0.0.1:9222/json/version | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data['webSocketDebuggerUrl'])
")
    export CDP_WS_URL
    echo "CDP Chrome already running: $CDP_WS_URL"
    exit 0
fi

# Start new Chrome instance
PROFILE_DIR="/tmp/chrome-cdp-profile-$$"
mkdir -p "$PROFILE_DIR"

nohup "$CHROME_PATH" \
    --headless \
    --no-sandbox \
    --disable-gpu \
    --disable-dev-shm-usage \
    --remote-debugging-port=9222 \
    --user-data-dir="$PROFILE_DIR" \
    >/tmp/chrome-cdp.log 2>&1 &

CHROME_PID=$!

# Wait for CDP to be ready
for i in {1..30}; do
    if curl -sf http://127.0.0.1:9222/json/version >/dev/null 2>&1; then
        CDP_WS_URL=$(curl -s http://127.0.0.1:9222/json/version | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data['webSocketDebuggerUrl'])
")
        export CDP_WS_URL
        echo "CDP Chrome started (pid $CHROME_PID): $CDP_WS_URL"
        exit 0
    fi
    sleep 0.5
done

echo "ERROR: CDP Chrome failed to start within 15s" >&2
kill $CHROME_PID 2>/dev/null || true
exit 1