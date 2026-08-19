# Chrome GPU Crash Fix — Ubuntu 24.04 Codespaces

## Problem

Chrome's GPU process crashes in container environments (exit_code=15 → "GPU process isn't usable" fatal error). The `--disable-gpu` flag alone is insufficient — Chrome still spawns a GPU process that crashes.

## Solution

Force software rendering via SwiftShader with these flags:

```bash
--disable-gpu-sandbox \
--disable-gpu-compositing \
--disable-accelerated-2d-canvas \
--disable-accelerated-video-decode \
--disable-webgl \
--use-gl=swiftshader
```

## Complete Chrome Launch (from lavish_planning_gui.sh)

```bash
DISPLAY=":99" /usr/bin/google-chrome-stable \
  --no-sandbox \
  --disable-gpu \
  --disable-software-rasterizer \
  --disable-dev-shm-usage \
  --disable-gpu-sandbox \
  --disable-gpu-compositing \
  --disable-accelerated-2d-canvas \
  --disable-accelerated-video-decode \
  --disable-webgl \
  --use-gl=swiftshader \
  --user-data-dir="/tmp/chrome-gui" \
  --new-window "http://127.0.0.1:4387/session/KEY" \
  >/tmp/chrome-gui.log 2>&1 &
```

## Verification

```bash
# Check Chrome is running
pgrep -f "chrome.*chrome-gui"

# Check log for errors
cat /tmp/chrome-gui.log
```

## Notes

- Works on Ubuntu 24.04 in GitHub Codespaces (no chromium deb available)
- Requires Google Chrome `.deb` install (prereq script handles this)
- SwiftShader is included in Chrome, no extra install needed
- The `--no-sandbox` flag is required in containers without user namespaces