# Proposal: Codespace Keepalive — Mimic Client Activity to Avoid Idle Shutdown

> **Status**: PROPOSED — awaiting user review before implementation
> **Date**: 2026-08-02
> **Goal**: Keep a headless / intermittently-attended Hermes-CodeSpace alive past GitHub's idle-timeout, so background jobs (Ollama pulls, model inference, long agent runs) aren't cut off.
> **Companion**: [codespace-playbook.md](codespace-playbook.md) — general Codespace ops. Article: how the container is kept alive.

---

## TL;DR

GitHub shuts a codespace down when it considers it **idle** for a configurable period (default 30 min). Idle is **not** measured by CPU/RAM — it is measured by whether an *interactive client* is connected and emitting activity (typing, mouse, terminal input/output). Long-running headless processes (hermes gateway, ollama) do **not** count as activity.

This proposal ships a `keepalive.sh` that (A) emits periodic terminal output to mimic ongoing client activity, and (B) hits the server's internal `/delay-shutdown` endpoint as a belt-and-suspenders reset. Wired into `start-hermes.sh` so it survives every codespace start.

**Honest caveat up front:** layer-2 (platform idle) detection is a GitHub-side heuristic and its exact heartbeat cadence is not published. Approach A is the only one grounded in GitHub's *documented* definition of activity ("terminal activity, either input or output"); B defends only the internal timer. Neither is a guarantee.

---

## Background: How idle shutdown actually works (from live investigation)

Investigation of the running container (server version 1.131.0) found **two independent shutdown layers**:

### Layer 1 — VS Code server internal auto-shutdown (5 min grace)

The server is started with `--enable-remote-auto-shutdown`. Its `ServerLifetime` service tracks **consumers** (active client connections):

```js
// out/server-main.js (the running code)
Z8 = 300 * 1e3                       // 5-minute grace timer

active(name){ totalCount++; cancelShutdownTimer(); }     // a client attached
inactive(name){ totalCount--; if (totalCount === 0 && enableAutoShutdown) _scheduleShutdown(); }

_scheduleShutdown(){ _shutdownTimer = setTimeout(_tryShutdown, Z8); }
_tryShutdown(){ if (totalCount > 0) abort; else process.exit(0); }
```

Consumers tracked: `ExtensionHost:<hash>`, `AgentHost`, PTY host + their websockets. When **all** clients drop, a **5-minute** timer arms; `/delay-shutdown` resets it.

### Layer 2: the GitHub platform idle policy (the real cutoff)

GitHub decides the codespace is idle when **no interactive client is present and sending activity** — typing, mouse, **terminal input or output** all reset the timer. This drives the **30-minute default** (5–240 min configurable; org policies can cap it) and is what *actually bills and cuts you off*. A silent HTTP ping to an internal endpoint does **not** look like an active client to the platform.

### Verified empirically in this container

- Server listening on `127.0.0.1:<port>` (found via `ss -lntp`).
- `GET /delay-shutdown` → **HTTP 200**, and notably returns **200 even with no auth / wrong token** (the handler runs before the token check — by design, the platform itself calls it).

---

## The Problem This Solves

In this repo, long-running headless services are started by `start-hermes.sh`:

- Hermes gateway (`019... hermes gateway run`)
- Hermes dashboard (port 9119)
- Ollama serve + model pulls

If you close the editor / stop interacting, the platform will idle the codespace out at the configured timeout even though Ollama is mid-pull or Hermes is mid-task. The container's own CPU/RAM usage does **not** keep it alive.

---

## Design

### Approach A (primary) — mimic terminal activity

Periodically write a small heartbeat line to the stdout of the session terminal. Because the standing hermes CLI runs attached to a VS Code pty (e.g. `pts/0`), emitting output on that terminal is the same class of signal GitHub's docs call "terminal output" → counts as activity.

### Approach B (safety net) — ping `/delay-shutdown`

Every few minutes, hit the internal endpoint to reset the layer-1 5-minute arm and to mirror what the platform's own keepalive does:
```
curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:<port>/delay-shutdown"
```
No auth needed (verified). Cheap and idempotent.

### Buffers / thresholds (proposal, tune in review)

| Item | Value | Rationale |
|------|-------|-----------|
| Keepalive period | 10 min | Below the relaxed default (30 min) and any 5-min internal arm |
| Pinger period | 4 min | Always < 5-min server arm, leaves margin |
| Terminal line | `\r\b·` style no-op / heartbeat | Low noise, doesn't spam scrollback |

---

## Proposed new file: `.devcontainer/keepalive.sh`

```bash
#!/usr/bin/env bash
# keepalive.sh — keep the Codespace "active" to avoid idle shutdown.
#                           (A) periodic terminal output on the session tty
#                           (B) internal /delay-shutdown pinger
#
# Safe to run as a background service. Wired into start-hermes.sh.

LOOP=600          # terminal-heartbeat every 10 min
PING_DELAY=240    # /delay-shutdown every 4 min

fatal(){ echo "[keepalive] FATAL: $*" >&2; exit 1; }

# Discover the VS Code server port (server-main) from listening sockets
find_server_port(){
  local p
  p=$(ss -ltnp 2>/dev/null | grep -oP 'server-main(?= \\))' && echo none)
  # fallback: parse from pgrep server-main cmdline --port
  ...
}
```

> NOTE: sketching here; exact port-discovery + tty-write logic is filled in during implementation. Keeping this wiki article at summary depth; full code lands in the script.

---

## Wiring into `start-hermes.sh`

Append (before the health self-check) an idempotent launch:

```bash
# 7. Start keepalive (idempotent) — keeps codespace from idle-shutting-down
if ! pgrep -f 'keepalive.sh' > /dev/null; then
  echo "[start-hermes] Starting keepalive..."
  setsid nohup "$SCRIPT_DIR/keepalive.sh" >> /tmp/keepalive.log 2>&1 &
fi
```

Since `start-hermes.sh` runs on **every** start/rebuild, keepalive comes back up automatically. `pgrep -f` guards against duplicates.

---

## Key Decisions (for review)

1. **Keepalive is opt-in** — started by start-hermes, easy to disable by commenting the block. Not force-advertised as a guarantee.
2. **Low-noise terminal output** — prefer a carriage-return overwrite heartbeat over log spam, so the terminal doesn't fill with junk.
3. **Ping every 4 min, heartbeat every 10 min** — deliberately well under both the internal 5-min arm and the default 30-min policy.
4. **Honest messaging** — the wiki and script comments state layer-2 is heuristic and may still cut in; this is a best-effort workaround, not a contract.

---

## Open questions / things to confirm before/while implementing

1. **Does writing to the session `tty` (e.g. the pty hermes runs on) actually survive / reachable when user has no VS Code open?** The platform may only count activity from a *present-ed* client session. If not, A degrades to B.
2. **What is the real layer-2 heartbeat cadence?** Unpublished. We tune by experiment (set a short timeout, observe).
3. **Org policy cap** — if your org caps idle below our pinger interval, we must tune accordingly (or detect and warn).
4. **Port discovery** — server port is dynamic (`--port 0`). keepalive must detect it from `/proc/<pid>/net` or `lsof`/`ss`/`/proc`.

---

## Success criteria

- Background-only bringup: after closing the VS Code tab (no manual client), the codespace remains alive/active longer than the configured policy timeout.
- `keepalive.sh` survives a codespace restart (wired into start-hermes.sh).
- No runaway output: terminal isn't flooded, `.keepalive.log` is bounded.
- If it still idles out, the wiki documents that it's heuristic and the experiment shows it, so we don't re-litigate.

---

## Risks / trade-offs

- **Billing**: keeping the codespace active longer means it's billed longer. This is the intended trade-off when a long task is running, but it's the explicit contract.
- **GitHub may change the internal scheme** (rename/remove `/delay-shutdown`, change client-presence heuristics) — keepalive must be resilient / fail-soft (if the endpoint disappears, just skip; don't crash).
- **No hard guarantee** — layer-2 is a heuristic. Treat as best-effort.

---

## See also

- [codespace-lifecycle.md](codespace-lifecycle.md) — reference: how Codespaces detects idle & shuts down, diagnosing container death.
- [codespace-playbook.md](codespace-playbook.md) — GitHub auth, PR monitoring, git push.

---

*This is a living proposal. Update it whenever the mechanism or tested results clarify.*
