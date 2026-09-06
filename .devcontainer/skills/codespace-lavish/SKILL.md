---
name: codespace-lavish
description: Launch a headed Lavish-AXI whiteboard over noVNC in Codespaces.
version: 0.1.0
author: gitricko, Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [lavish, mermaid, whiteboard, codespace, gui, novnc]
    related_skills: [codespace-port-visibility]
---

# Codespace Lavish Skill

Launch a headed Lavish-AXI planning whiteboard on a virtual X display, bridge it to
noVNC, and start the feedback poll so the user can iterate visually. Self-installing:
it verifies prerequisites and installs missing ones — it never assumes the Codespace
is pre-provisioned.

## When to Use

- User says "planning lavish", "plan this in lavish", or "open a lavish whiteboard".
- User wants a visual, editable Mermaid/HTML planning board rendered in a browser they
  can watch over noVNC.
- Don't use for: headless browser automation (use `cdp-browser-testing`).

## Prerequisites

- `bash`, `node` >= 18, `npm` on PATH.
- `sudo`/root for apt installs (the `--fix` path installs system packages).
- Network access to download Google Chrome `.deb` and `lavish-axi` via npx.
- All other deps (Xvfb, openbox, x11vnc, websockify, novnc, a browser) are checked and
  installed by the prerequisite script — do not pre-check them by hand.

## How to Run

Through the `terminal` tool (scripts are repo-relative under the skill dir):

```
terminal(command="bash .devcontainer/skills/codespace-lavish/scripts/lavish_planning_gui.sh --fix", timeout=300)
```

Optional arguments:
- `--fix` — install missing prerequisites (required on a fresh Codespace).
- `<artifact.html>` — open a specific HTML artifact instead of generating one.
- `--prompt "..."` — generate a planning artifact from a free-form prompt.
- `--monitor` — tail the poll log for live feedback after launch (Ctrl+C to exit).

## Quick Reference

```
# First run on a fresh Codespace (installs deps, launches everything):
bash .devcontainer/skills/codespace-lavish/scripts/lavish_planning_gui.sh --fix

# Open a specific artifact:
bash .devcontainer/skills/codespace-lavish/scripts/lavish_planning_gui.sh path/to/plan.html

# Generate from a prompt:
bash .devcontainer/skills/codespace-lavish/scripts/lavish_planning_gui.sh --prompt "Plan the Q3 launch"

# Generate and monitor feedback live:
bash .devcontainer/skills/codespace-lavish/scripts/lavish_planning_gui.sh --prompt "Plan the Q3 launch" --monitor

# Just check prerequisites (no launch):
bash .devcontainer/skills/codespace-lavish/scripts/lavish_planning_prereqs.sh --fix
```

## Procedure

1. Run the prerequisite check via `lavish_planning_prereqs.sh`. If it reports failures
   and you passed `--fix`, it installs them; if you did not pass `--fix`, re-run with it.
   *Completion: `RESULT: ALL REQUIRED PREREQUISITES MET`.*
2. Launch the GUI stack: Xvfb :99 + openbox + Chrome (on :99) + x11vnc (:5900) +
   websockify/noVNC (:6080). *Completion: `curl -s localhost:6080/vnc.html` returns 200.*
3. Start the Lavish-AXI engine on loopback (default 4387) and open the artifact session.
   *Completion: `curl -s 127.0.0.1:4387/health` returns `{"ok":true}` and
   `/session/<key>` returns 200.*
4. Start the poll listener (background, auto-restarting) so user feedback in the whiteboard is continuously received.
   *Completion: a `lavish-axi poll` process is running, `/tmp/lavish-poll.log` is being written, and the noVNC URL is printed.*
5. Hand the user the noVNC URL (with auto-connect and local scaling):
   `https://<codespace>-6080.app.github.dev/vnc.html?autoconnect=true&resize=scale`
   Set port 6080 to PRIVATE in the Codespace UI for auth-gated access.
   *Completion: user can open the URL and see the whiteboard immediately (no connect click needed, viewport scales to fit).*
6. (Optional) Run with `--monitor` to tail the poll log and see live feedback as the user interacts with the whiteboard.

## Pitfalls

- **Browser on Ubuntu 24.04:** there is NO `chromium` apt deb (snap-transitional, snap
  unavailable in container). The prereq script installs Google Chrome's `.deb` instead.
  Don't "fix" this by adding `chromium` to an apt line — it will fail on a fresh build.
- **Poll loop is mandatory:** Lavish is request/response. Without a running `poll`, user
  feedback in the whiteboard goes nowhere. If the whiteboard seems unresponsive, verify
  a `lavish-axi poll` process is alive (see `/tmp/lavish-poll.log`).
- **Poll process must be disowned:** The background poll loop (`while true; do poll; done`)
  must run with `disown` so it survives the parent script exiting. Without disown, the
  poll dies when the terminal tool returns.
- **VNC stack is persistent:** The Xvfb/openbox/Chrome/x11vnc/websockify/lavish-axi stack
  stays running after launch. Only stop it if the user explicitly asks. Do not kill the
  browser or VNC services just because the launch script completed.
- **Killing Chrome to reload:** match the process by exact name `chrome` + its
  `--user-data-dir=/tmp/chrome-gui`, never by a `pgrep -f` pattern that also appears in
  your own command line (it will kill your own shell).
- **Port 4387 vs dynamic slots:** this skill uses the reserved default 4387 so the GUI
  URL stays stable. The `lavish-axi` skill's dynamic 43XX slots are a separate concern.
- **Artifact load tokens are ephemeral:** The `loadToken` from the session page expires
  quickly. Direct `curl` to `/artifact/<key>/index.html?loadToken=...` will return
  "Artifact load expired". The artifact is served correctly inside the noVNC iframe
  when Chrome loads the session page — do not try to fetch it directly for verification.
  Verify via `curl 127.0.0.1:4387/health` and `curl 127.0.0.1:6080/vnc.html` instead.
- **Chrome GPU crashes on Ubuntu 24.04:** In Codespace containers, Chrome's GPU process
  crashes (exit_code=15) causing "GPU process isn't usable" fatal error. Fix: pass
  `--disable-gpu-sandbox --disable-gpu-compositing --disable-accelerated-2d-canvas
  --disable-accelerated-video-decode --disable-webgl --use-gl=swiftshader` to force
  software rendering via SwiftShader. Added to `lavish_planning_gui.sh` Chrome launch.
- **noVNC auto-connect + scaling via query string:** The URL
  `https://<codespace>-6080.app.github.dev/vnc.html?autoconnect=true&resize=scale`
  enables automatic VNC connection (no "Connect" button) and local viewport scaling
  (fits to browser window). These are read by noVNC's `WebUtil.getConfigVar()` from
  the query string/hash on page load.
- **Poll process survival:** The disowned background poll loop can still die when the
  launching shell exits. The script now uses `disown -h $POLL_PID 2>/dev/null || true`
  (mark as no-hup) and the while-true loop restarts on exit. For maximum persistence,
  start the poll as a separate tracked background job if the harness supports it.
- **Agent reply spinner:** The `poll --agent-reply` command delivers the message then
  enters long-polling, showing a "working" spinner in the Lavish UI. This is temporary
  and does NOT block the chat input — users can still type/send messages. The background
  poll loop (without `--agent-reply`) runs without a spinner.
- **Argument parsing for `--prompt`:** Use single-pass loop with `((i++))` to consume
  the next argument; two-pass approaches with a pending variable lose the value.

## References

- `references/session-learnings.md` — session-specific patterns, pitfalls, and workarounds (Ubuntu 24.04 chromium, pgrep self-match, lavish poll loop, prerequisite check pattern, npx resolution)
- `references/artifact-tokens.md` — artifact load token behavior and verification pitfalls
- `references/chrome-gpu-fix.md` — Chrome GPU crash fix for Ubuntu 24.04 Codespaces (SwiftShader flags)

## Verification

- `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:6080/vnc.html` → `200`.
- `curl -s http://127.0.0.1:4387/health` → `{"ok":true,...}`.
- `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:4387/session/<key>` → `200`.
- A `pgrep -f "lavish-axi poll"` process exists (auto-restarts on exit).
- `/tmp/lavish-poll.log` receives feedback entries as user interacts.
- `--monitor` flag tails the poll log for live feedback.
- noVNC URL with `?autoconnect=true&resize=scale` auto-connects and scales viewport.
- Opening the noVNC URL shows Chrome rendering the artifact on the virtual display.

## For Future Agents — Quick Start

If you're an agent picking up this task:

```bash
# 1. Ensure you're in the repo root
cd /workspaces/hermes-codespace

# 2. Launch with --fix on fresh Codespace (installs all deps)
bash .devcontainer/skills/codespace-lavish/scripts/lavish_planning_gui.sh --fix --prompt "Your planning prompt here"

# 3. Or with a specific artifact:
bash .devcontainer/skills/codespace-lavish/scripts/lavish_planning_gui.sh --fix path/to/artifact.html

# 4. For live feedback monitoring:
bash .devcontainer/skills/codespace-lavish/scripts/lavish_planning_gui.sh --fix --prompt "..." --monitor

# 5. Check if already running (skip --fix):
curl -s http://127.0.0.1:4387/health
# If ok: just run without --fix
```

The script is idempotent — safe to re-run. It detects running services and only starts missing ones.