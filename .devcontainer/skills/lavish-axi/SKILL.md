---
name: lavish-axi
description: Launch a dedicated lavish-axi planning session per Hermes conversation with zero port collisions — "iterate this in lavish" spins up an isolated, annotated artifact on a dynamic slot.
---

# lavish-axi skill

Run lavish-axi planning sessions inside a GitHub Codespace without fixed-port collisions.
Each Hermes conversation gets its own **slot**: a loopback lavish-axi engine, a public nginx
proxy, and a poll listener — all keyed by the Hermes session ID and persisted in a slot registry.

## When to use

- User says "iterate this in lavish", "plan in lavish", or wants a visual annotated planning artifact.
- You need to draft/iterate a spec, diagram, or design with user annotations + chat feedback.
- Multiple Hermes sessions may run lavish at once (dynamic ports avoid collisions).

## Architecture

```
Hermes session ──reads session ID──> slot_allocator.py
                                      │  slots.json: {slot, engine_port, public_port, state_dir, hermes_session_id}
                                      ▼
                            launch_slot.py
                              ├─ start lavish-axi engine  (127.0.0.1:43XX, loopback)
                              ├─ nginx proxy              (0.0.0.0:99XX → 127.0.0.1:43XX, Origin rewrite)
                              ├─ expose_port.py           (gh forward + visibility, public)
                              └─ print public URL
                                      ▼
                            poll_supervisor.py  (harness background, restarts poll per cycle)
```

Port scheme (matching suffixes for readability):
- Engine (loopback): `4387 + (slot-1)` → 4387, 4388, 4389…
- Public (nginx): `9987 + (slot-1)` → 9987, 9988, 9989…

## Quick start

```bash
# 1. Allocate slot for THIS Hermes session, launch engine + nginx + expose
python3 scripts/launch_slot.py "$HERMES_SESSION_ID" /path/to/artifact.html

# 2. Start poll supervisor as harness-background (notify_on_complete=true)
python3 scripts/poll_supervisor.py <state_dir> <artifact_path> <engine_port>

# 3. Drop the public URL from launch_slot output into chat
```

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/slot_allocator.py` | Registry: `alloc <session_id> [artifact]`, `get`, `list`, `release`. Maps Hermes session → slot ports/state. |
| `scripts/launch_slot.py` | Bring a slot online: engine + nginx + public expose. Prints public URL. |
| `scripts/poll_supervisor.py` | Keep `lavish-axi poll` alive (re-runs after each feedback cycle). Run as harness background. |
| `scripts/nginx_slot.template` | nginx config template (Origin rewrite + WebSocket upgrade). |

## Critical rules

1. **Poll MUST run with `LAVISH_AXI_PORT` = the slot's engine port** and `LAVISH_AXI_STATE_DIR` = the slot's state dir. Mismatch → "No active session" error.
2. **Engine is loopback-only** (`127.0.0.1:43XX`). Never expose it; nginx (99XX) is the public face.
3. **Public port needs both steps**: `gh codespace ports forward <port>:<diff-local>` then `visibility <port>:public`. `expose_port.py` (from `codespace-port-visibility` skill) does both.
4. **Artifact stays as a chat link** — Codespace auto-open goes to `/`, not `/session/xxx`.
5. **Mermaid**: use in-page Mermaid (`theme: "dark"`). Defer the whiteboard iframe (GitHub warning on public URLs).

## Slot registry persistence

`~/.lavish-axi/slots.json` survives restarts. On "iterate this in lavish", the agent calls
`slot_allocator.py get <session_id>` first — if a slot exists, reuse it; otherwise `alloc`.
This is how multiple Hermes sessions each own a stable slot.

## Files

- Skill: `.devcontainer/skills/lavish-axi/`
- Wiki design: `.devcontainer/wiki/lavish-axi-skill-design.md`
- Setup/troubleshooting: `.devcontainer/wiki/lavish-axi-codespace-setup.md`
- Depends on: `codespace-port-visibility` skill (`expose_port.py`)
