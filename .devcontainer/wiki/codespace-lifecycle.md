# GitHub Codespaces Lifecycle: Idle Detection & Shutdown

> Reference article (LM Wiki). **Skill** = procedural ("how to do X") → `.devcontainer/skills/`.
> **Wiki article** = reference knowledge ("how system Y works") → this directory.
> Related: [keepalive-proposal.md](keepalive-proposal.md) — the concrete keepalive
> implementation for keeping a headless codebox alive.

This explains how GitHub decides a codespace is "idle" and terminates it, and
how to keep one alive when a background agent/job must outlive a closed editor.
It is the territory *underneath* [codespace-playbook.md](codespace-playbook.md)
(which covers auth/CI/debug). Use this when the question is: *"will my container
get killed, and how do I prevent it?"*

## The key insight

**Idle detection is NOT about CPU/RAM load inside the container.** It is driven
by whether a **client connection ("consumer")** is attached and sending activity:

- A connected editor that you use (typing/scrolling) and terminal input **or
  output** resets the idle timer.
- Headless services inside the container (web servers, ollama, model relay, an
  agent daemon) do **NOT** keep the codespace alive on their own.
- Closing the editor tab / walking away drops the client connection and starts
  the idle countdown.

Consequence: a long background job that prints nothing and has no terminal
attached still hits the timeout and gets killed — even while CPU is busy.

## Server-side mechanism (verified against running source)

The in-container VS Code server is launched with `--enable-remote-auto-shutdown`.
Its `serverLifetimeService` tracks "consumers" — active client connections:

- `active(name)`  -> `totalCount++`, cancels the shutdown timer.
- `inactive(name)` -> `totalCount--`; when `totalCount == 0` and auto-shutdown is
  on, it schedules shutdown.
- Shutdown waits a **5-minute grace window** (`Z8 = 300 * 1e3` ms in
  `server-main.js`), reset by any newly active consumer.
- `_tryShutdown()` calls `process.exit(0)` once `totalCount == 0`.

Consumers observed: `ExtensionHost:<hash>`, `AgentHost`, plus the PTY host and
its websockets. An HTTP endpoint `/delay-shutdown` calls `delay()` to reset the
timer (this is how GitHub's platform layer keeps codespaces managed).

The client (desktop/web editor) holds a persistent socket and sends a periodic
SSH-style keep-alive (the codespaces extension uses `keepalive@openssh.com` and
`keepAliveIntervalInSeconds`) — that is the "am I alive" signal that resets idle.

## Configuring / reading the timeout

- Default idle timeout: **30 minutes** of inactivity.
- User setting: range **5 – 240 min**, at GitHub -> Settings -> Codespaces ->
  "Default idle timeout".
- Per-codespace: `gh codespace create --idle-timeout 90m`.
- Orgs can enforce a **max** idle timeout overriding the user's setting.
- Billing runs while active — an idle-but-still-running codespace is still
  billed until it times out.

## Diagnosing "why did my codespace die"

1. Check the launched server flag:
   `ps aux | grep server-main.js | grep -o 'enable-remote-auto-shutdown'`
   (present = auto-shutdown is armed).
2. Check whether a client connection is attached: `server-main.js` and
   `bootstrap-fork --type=extensionHost/ptyHost` processes must be running.
   Headless-only containers (agent + portal, no editor client) have no consumer
   -> they are reaped on timeout.
3. Tail the VS Code server log dir:
   `/home/codespace/.vscode-remote/data/logs/<timestamp>/` for
   `ServerLifetime: all consumers inactive, shutting down` messages.

## Keeping a codespace (or job) alive

- **Keep a real client attached** — a VS Code / web editor you interact with;
  terminal I/O resets the timer.
- **Periodic terminal activity** — a light job writing to a terminal a few
  times per idle window (respects the "terminal output resets timeout" rule).
  Do NOT fake it with a tight infinite loop unless you accept maximum billing.
- **Raise the configured timeout** (Settings or `--idle-timeout`), e.g. for a
  big headless build.
- For a headless agent that must survive editor close: prefer a mechanism that
  touches an attached client or emits periodic terminal output (see
  [keepalive-proposal.md](keepalive-proposal.md)); a bare `nohup`/`setsid`
  service is **not** enough on its own.

## Pitfalls

- Do not assume a running web server, ollama, or dashboard process counts as
  "active." Consumers = client connections, not background services.
- The 5-min grace period only covers transient disconnects, not prolonged
  absence.
- `GITHUB_CODESPACE_TOKEN` / `GH_TOKEN` are unrelated to lifecycle; keep auth
  concerns in [codespace-playbook.md](codespace-playbook.md).

## See also

- [keepalive-proposal.md](keepalive-proposal.md) — keepalive.sh design + A/B.
- [codespace-playbook.md](codespace-playbook.md) — auth, PRs, git push.
- `skill:github-codespace` — GitHub Codespaces auth/CI/debug in one skill.

*Last updated: 2026-08-02*
