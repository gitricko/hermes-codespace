# Lavish-AXI Skill Design

Design spec for the `codespace/lavish-axi` skill — launching a dedicated, annotated
lavish-axi planning session per Hermes conversation, with zero fixed-port collisions.

## Problem

lavish-axi binds a fixed port (default `4387`) and we front it with nginx. One Codespace
= one public port range. Two parallel Hermes sessions running lavish would collide.
We want **multiple simultaneous lavish planning sessions**, each tied to its own Hermes
conversation.

## Key findings from source (paths.js / server.js)

- `LAVISH_AXI_PORT` — per-server bind port. Each instance picks its own.
- `LAVISH_AXI_STATE_DIR` — isolates sessions, polls, keys per instance.
- Sessions keyed by `sha256(realpath(artifact))` — one server serves many artifacts.

## Design: per-session "slot"

| Slot | Engine (loopback) | Public (nginx) | State dir | Hermes Session ID |
|------|-------------------|----------------|-----------|-------------------|
| 1 | 4388 | 9988 | `~/.lavish-axi/slot-1` | from current session |
| 2 | 4389 | 9989 | `~/.lavish-axi/slot-2` | from current session |
| N | 4387+N | 9987+N | `~/.lavish-axi/slot-N` | from current session |

Port scheme: engine `43XX`, public `99XX`, **matching last two digits** for readability.
(`4387` reserved for legacy/default instance.)

### Slot registry

`~/.lavish-axi/slots.json` maps:
```json
{
  "slot": 1,
  "engine_port": 4388,
  "public_port": 9988,
  "state_dir": "/home/codespace/.lavish-axi/slot-1",
  "hermes_session_id": "<id>",
  "artifact_path": "/workspaces/lavish-axi/proposal-lavish-skill.html",
  "session_key": "5bb3131bd2bb6cc1",
  "created_at": "2026-08-14T..."
}
```
On "iterate this in lavish", the agent reads the current Hermes session ID, calls
`slot_allocator.py get <id>` — if a slot exists, reuse it; otherwise `alloc`. The registry
survives restarts, so each Hermes conversation owns a stable slot.

## Trigger phrase

`iterate this in lavish` (or `plan in lavish`) → agent:
1. Reads current Hermes session ID.
2. Allocates/finds slot via `slot_allocator.py`.
3. Writes artifact (HTML) to a path.
4. Runs `launch_slot.py <session_id> <artifact_path>` → engine + nginx + public URL.
5. Starts `poll_supervisor.py` as harness background (notify_on_complete=true).
6. Drops public URL in chat (link, not auto-open).

## Public port exposure

Uses `codespace-port-visibility` skill's `expose_port.py <port>` which runs:
```bash
gh codespace ports forward <port>:<port+10000>   # registers tunnel
gh codespace ports visibility <port>:public       # flips visibility
```
Without the `forward` step, `visibility` returns 404 (GitHub backend doesn't know the tunnel).

## Poll supervisor

lavish-axi `poll` is a long-poll: captures one feedback, returns, exits. The supervisor
re-runs it after each cycle so the listener stays alive. **Critical:** the poll MUST run with
`LAVISH_AXI_PORT` = the slot's engine port and `LAVISH_AXI_STATE_DIR` = the slot's state dir.
Mismatch → "No active session for this file".

## Feedback cycle

```
User annotates in lavish → POST /api/:key/prompts → poll captures (status: feedback, exits)
  → agent processes → POST /api/:key/agent-reply → renders as AGENT bubble
  → supervisor restarts poll → waiting for next feedback
```

## Files

- Skill: `.devcontainer/skills/codespace/lavish-axi/`
  - `scripts/slot_allocator.py` — registry
  - `scripts/launch_slot.py` — engine + nginx + expose
  - `scripts/poll_supervisor.py` — keep poll alive
  - `scripts/nginx_slot.template` — nginx config
  - `SKILL.md`
- Wiki: `.devcontainer/wiki/lavish-axi-codespace-setup.md` (setup/troubleshooting)
- Depends on: `codespace-port-visibility` skill

## Open questions — RESOLVED

- **Session ownership** → Hermes session ID in slot registry (persists across restarts).
- **Auto-open vs link** → Link in chat (Codespace auto-open hits `/` not `/session/xxx`).
- **Mermaid iframe** → Deferred. Use in-page Mermaid (`theme: "dark"`); skip whiteboard iframe on public URLs.
- **HTML vs MD** → HTML = living lavish scratchpad (optional repo artifact); MD = permanent wiki record.
