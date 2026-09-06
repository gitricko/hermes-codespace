# Codespace Lavish — Headed Whiteboard over noVNC

## Overview

This skill launches a **headed Lavish-AXI planning whiteboard** inside a GitHub Codespace, bridging the virtual X display to a browser via **noVNC**. The user can open the noVNC URL in their local browser and interact with a live Mermaid/HTML whiteboard rendered by Chrome on the virtual display.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Codespace Container                                            │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐           │
│  │  Xvfb   │  │ openbox │  │ Chrome  │  │ x11vnc  │           │
│  │  :99    │──│ (WM)    │──│ (headed)│──│ :5900   │           │
│  └─────────┘  └─────────┘  └─────────┘  └────┬────┘           │
│                                               │                │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐       │                │
│  │websockify│──│ noVNC   │  │Lavish-AXI│◄─────┘                │
│  │ :6080   │  │ :6080   │  │ :4387   │    (poll loop)         │
│  └─────────┘  └─────────┘  └─────────┘                        │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
   ┌──────────────┐
   │ User Browser │  (opens https://<codespace>-6080.app.github.dev/vnc.html?autoconnect=true&resize=scale)
   └──────────────┘
```

## Key Components

| Component | Role | Port/Display |
|-----------|------|--------------|
| Xvfb | Virtual X11 display | :99 |
| openbox | Window manager | (on :99) |
| Google Chrome | Headed browser rendering artifact (SwiftShader software render) | (on :99) |
| x11vnc | VNC server exporting :99 | 5900 (RFB) |
| websockify | VNC → WebSocket bridge | 6080 (WS) |
| noVNC | Web VNC client (auto-connect, local scaling) | 6080 (served by websockify) |
| lavish-axi | Planning engine + poll loop | 4387 |

## Chrome GPU Crash Fix (Ubuntu 24.04 Codespaces)

Chrome's GPU process crashes in container environments (exit_code=15 → "GPU process isn't usable"). The fix is to force software rendering via SwiftShader:

```bash
--disable-gpu-sandbox --disable-gpu-compositing --disable-accelerated-2d-canvas \
--disable-accelerated-video-decode --disable-webgl --use-gl=swiftshader
```

These flags are baked into `lavish_planning_gui.sh` Chrome launch. The `--disable-gpu` flag alone is insufficient — Chrome still spawns a GPU process that crashes.

## noVNC Auto-Connect + Scaling

noVNC reads configuration from query string/hash via `WebUtil.getConfigVar()`. The skill generates:

```
https://<codespace>-6080.app.github.dev/vnc.html?autoconnect=true&resize=scale
```

| Parameter | Effect |
|-----------|--------|
| `autoconnect=true` | Auto-connects to VNC server on page load (skips "Connect" button) |
| `resize=scale` | Local scaling mode — viewport scales to fit browser window |

## Session Key

The session key is derived deterministically from the artifact path:
```bash
SHA256(realpath(artifact))[:16]
```
This ensures the same artifact always maps to the same `/session/<key>` endpoint.

## Feedback Loop (Critical)

Lavish-AXI is **request/response**. The `poll` process **must run continuously**:
- User edits in whiteboard → queued in Lavish
- `lavish-axi poll <artifact>` long-polls `/session/<key>/poll`
- Feedback delivered, printed, process exits 0 → **auto-restarts every 2s**

The skill starts poll in background with auto-restart loop and prints its PID.
Use `--monitor` to tail the poll log for live feedback.

## Prerequisites

All deps are auto-installed by `lavish_planning_prereqs.sh --fix`:
- Xvfb, openbox, x11vnc, websockify, novnc (apt)
- Google Chrome stable (`.deb` on Ubuntu 24.04 — no chromium deb)
- node ≥ 18, npm
- lavish-axi (resolved via `npx --yes lavish-axi` on first run)

## Usage

```bash
# First run (installs deps, launches everything):
bash .devcontainer/skills/codespace-lavish/scripts/lavish_planning_gui.sh --fix

# Open existing artifact:
bash .devcontainer/skills/codespace-lavish/scripts/lavish_planning_gui.sh path/to/plan.html

# Generate from prompt:
bash .devcontainer/skills/codespace-lavish/scripts/lavish_planning_gui.sh --prompt "Plan the Q3 launch"

# Generate and monitor feedback live:
bash .devcontainer/skills/codespace-lavish/scripts/lavish_planning_gui.sh --prompt "Plan the Q3 launch" --monitor

# Prereq check only:
bash .devcontainer/skills/codespace-lavish/scripts/lavish_planning_prereqs.sh --fix
```

## Port Visibility

Port 6080 (noVNC) should be set to **PRIVATE** for auth-gated access:
```bash
python3 .devcontainer/skills/codespace-port-visibility/scripts/set_port_visibility.py 6080 private
```

## Related

- Skill: `codespace-lavish` — procedural how-to (this skill)
- Skill: `codespace-port-visibility` — port visibility automation
- Wiki: `codespace-lavish.md` (this article)
- References: `references/session-learnings.md` — detailed pitfalls & patterns
- References: `references/artifact-tokens.md` — artifact load token behavior and verification pitfalls