---
name: lavish-axi
description: Run lavish-axi planning sessions in GitHub Codespaces.
version: "1.0.0"
category: codespace
tags: [lavish-axi, codespace, planning, annotation, multi-slot, nginx, port-visibility]
---

# Lavish-AXI in GitHub Codespaces

## When to use

- User says "iterate this in lavish", "plan in lavish", "open a lavish session", or wants an
  annotated, chat-driven planning/design surface inside a Codespace.
- You need a shared visual artifact the user can annotate and chat about, with the agent
  capturing feedback and replying in-document.
- You need MULTIPLE simultaneous lavish sessions (one per Hermes conversation) without port
  collisions — use the dynamic slot scheme below.

## Architecture (verified working)

```
Browser (public URL)
   │
   ▼
nginx :99XX  (rewrites Origin/Host/Referer → 127.0.0.1:43XX)
   │
   ▼
lavish-axi server  127.0.0.1:43XX  (loopback only — DNS-rebind guard enforces this)
   │
   ▼
CDP Chrome :9222  (headless browser automation via cdp-browser-testing skill)
```

**Why nginx is required** (not direct port exposure):
- lavish-axi has a same-origin guard on `/prompts`. Behind a reverse proxy the expected origin is
  the validated `X-Forwarded-Host` + `X-Forwarded-Proto`. nginx rewrites `Origin`/`Host`/`Referer`
  to loopback so the guard passes.
- GitHub Codespace proxy conflicts with direct `*.app.github.dev` access (DNS-rebinding guard).
- Public port must be used for "Send to Agent" to work (private port is blocked by GitHub auth
  on the API). Mermaid whiteboard iframe shows a GitHub warning on public URLs — known limitation,
  deferred.

## Dynamic slot scheme (multi-session)

| Slot | Engine (loopback) | Public (nginx) | State dir |
|------|-------------------|----------------|-----------|
| 1 | 4387 | 9900 | `~/.lavish-axi` |
| 2 | 4388 | 9910 | `~/.lavish-axi/slot-2` |
| N | 4386+N | 9900+(N-1)*10 | `~/.lavish-axi/slot-N` |

- **Use 99XX for public ports, NOT 80XX** — 8080/8081 collide with common dev tools. User-mandated.
- Engine ports are loopback-only and never exposed, so less critical.
- Allocate the next free slot from a registry: `~/.lavish-axi/slots.json`
  (`{"slots":[{"n":1,"engine":4387,"public":9900,"artifact":"/abs/path","state_dir":"~/.lavish-axi","hermes_session":"<id>"}]}`).
- Each slot = 1 lavish-axi server + 1 nginx server block + 1 poll listener, tagged with the
  Hermes session id (so restart can re-map).

## Setup steps (per slot)

```bash
# 1. Start engine (loopback) with isolated state
LAVISH_AXI_PORT=4388 LAVISH_AXI_STATE_DIR=~/.lavish-axi/slot-2 \
  LAVISH_AXI_NO_OPEN=1 node dist/cli.mjs server --port 4388

# 2. nginx server block → /etc/nginx/sites-available/lavish-axi-slot2, symlink enabled, reload
#    (see references/nginx-slot.conf for the template — MUST rewrite Origin/Host/Referer)

# 3. Expose public port with zero manual clicks (see codespace-port-visibility skill)
python3 ~/.hermes/skills/codespace/codespace-port-visibility/scripts/expose_port.py 9910

# 4. Open the artifact on THIS slot's engine (creates the session)
LAVISH_AXI_PORT=4388 LAVISH_AXI_STATE_DIR=~/.lavish-axi/slot-2 \
  node dist/cli.mjs /workspaces/lavish-axi/proposal.html --no-open

# 5. Start the poll listener WITH the matching state dir (critical — see Pitfalls)
LAVISH_AXI_STATE_DIR=~/.lavish-axi/slot-2 node dist/cli.mjs poll /workspaces/lavish-axi/proposal.html
```

Session URL for the user: `https://<codespace>-<public>.app.github.dev/session/<key>`
where `<key>` = `sha256(realpath(artifact)).slice(0,16)`.

## Pitfalls (embedded from real failures)

- **lavish injects NO design system / CSS.** Your artifact HTML renders with browser-default
  styling (ugly, possibly invisible text on dark hosts). You MUST add a `<style>` block with an
  explicit background + readable text color. See `templates/proposal-artifact.html` for a known-good
  dark theme. The CLI emits a `self_paint_warning` when the page has no background — fix it before
  treating the artifact as presentable.
- **Poll 404 "No active Lavish Editor session"** when `LAVISH_AXI_STATE_DIR` for the poll does not
  match the state dir of the server that opened the session. Always pass the same `LAVISH_AXI_STATE_DIR`
  to both `server`/`poll`. The default state dir is `~/.lavish-axi` (slot 1 only).
- **nginx MUST rewrite `Origin`/`Host`/`Referer` to `127.0.0.1:43XX`** or the same-origin guard
  rejects `POST /prompts` with `cross-origin prompt submission rejected`. Copy the exact headers from
  `references/nginx-slot.conf`.
- **`gh codespace ports visibility` alone 404s** for a port GitHub's backend hasn't tunneled yet.
  Use `expose_port.py` (forward + visibility) from the codespace-port-visibility skill. `forward` binds
  a local side, so forward to `<port>+10000` to avoid clashing with the service already on `<port>`.
- **Poll is a long-poll that exits after capturing one feedback** (returns `status: feedback`). It is
  NOT a daemon. After it exits, run `lavish-axi poll <file> --agent-reply "<msg>"` to reply and
  re-enable sends, then restart the plain poll. Use a harness-native background job (notify_on_complete)
  so the completion resumes you.
- **Do NOT patch lavish-axi server.js** (e.g. `isSameOriginRequest`) to bypass the guard. The user
  reverted that; the nginx Origin-rewrite is the correct fix. `LAVISH_AXI_ALLOWED_HOSTS=*` also works
  but weakens the guard — not preferred.

## Proposal-in-lavish workflow (user preference)

User wants proposals authored as lavish artifacts (not `.md` files) so they can annotate inline.
Write the proposal HTML, open it on a slot, drop the public URL in chat. Capture their annotations
via the slot's poll. Iterate the artifact; lavish live-reloads on save.

## Related skills

- `codespace/codespace-port-visibility` — `expose_port.py` for zero-click public port exposure
- `codespace/cdp-browser-testing` — headless browser automation to drive the artifact (type, click, read chat)
- `codespace/github-codespace` — Codespace auth, CI, PR workflow

## Support files

- `references/nginx-slot.conf` — nginx server-block template (Origin rewrite)
- `references/slot-registry.md` — slots.json schema + allocation logic
- `templates/proposal-artifact.html` — styled dark-theme boilerplate for lavish proposals
- `scripts/launch-slot.sh` — one-shot slot launcher (engine + nginx + expose + open + poll)