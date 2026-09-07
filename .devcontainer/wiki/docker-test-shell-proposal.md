# Proposal: Docker Test Shell (`dts`) — Fresh-Environment Standalone Testing for Hermes Agent

> **Status**: PROPOSED — design proposal for review, not yet implemented
> **Date**: 2026-09-07
> **Goal**: Give Hermes (and future agents) one reusable way to test any tool in a *clean, throwaway Linux container* — so the working environment's installed libraries, stale config, and running services never mask or pollute the test.

---

## TL;DR

When an agent needs to test something in a Codespace, testing on the host is unreliable: the host already has Node, Python, pip packages, venvs, stale configs, and possibly running services. A passing host test proves nothing about a fresh install.

The answer is a tiny, reusable tool — **Docker Test Shell** — that exposes one primitive: **run a command inside a fresh, mounted, normal-user container**. The whole point is container isolation alone; everything else is plain shell. It is fully standalone: not tied to any specific project or stack.

## The one concept

> **Test inside a throwaway container so your own environment's installed libs, stale state, and services do not pollute the test.**

That is the entire tool. Not a test framework, not a schema, not verify primitives. Just: get me into a clean container with my code mounted in, and let me run commands.

## Why a reusable primitive, not a per-project script

A tightly-coupled test script (one that also knows how to install a specific stack, start its servers, check its config) is only reusable for that one project. The value worth generalizing is the *transport*: container lifecycle, bind-mount, uid-1000 user, TTY-aware exec, cleanup. Those are fiddly and easy to get wrong, and they apply to *any* target.

Dividing that out leaves:

- **`dts`** = the reusable transport (container isolation).
- **Target logic** = plain shell written per project, composed entirely of `dts exec` + bash checks.

A future agent testing a Node app, a Python package, or a shell installer all use the same primitive; only the few commands differ.

## Proposed design — Docker Test Shell (`dts`)

### The primitive

```
dts exec "<command>"     # run <command> inside a fresh, mounted, uid-1000 container
```

That is the core. Verification is plain shell around it:

```bash
dts exec "bash /src/install.sh"
dts exec "hermes --version" && echo "hermes ok"
curl --max-time 5 -sf http://127.0.0.1:20128/healthz && echo "server ok"
```

No `wait_port` / `http_ok` / `cmd_ok` primitives — those smuggle a framework back in. You have `exec`; bash does the rest.

### Three responsibilities `dts` owns (because they're fiddly)

| Command | Job | Why `dts` owns it |
|---------|-----|-------------------|
| `dts up` | Create container: fresh base image (configurable), live bind-mount of the current repo, run as uid‑1000 user; install nothing | Correct base, uid, mount flags; container isolation is the whole point |
| `dts exec` | `docker exec` with correct flags: `-i` for scripts/agents, `-it` for a human TTY; always `bash -l`; always the right user | TTY and user flags are easy to get wrong |
| `dts clean` | Remove the container | No orphan containers / disk leak |

### Configuring the base image

The base image is **configurable**, defaulting to `ubuntu:24.04`:

```
dts up                    # defaults to ubuntu:24.04
IMAGE=debian:12 dts up    # explicit override
```

Rationale: different targets need different bases (Alpine for musl, a Node image for node apps). One env var keeps it flexible without complexity.

### Installing apt packages (manual, one-off)

`dts up` installs **nothing**. When a target needs apt packages (e.g. `curl` for a server, `g++` for native modules), the agent installs them it taught one-off through `dts exec`:

```bash
dts exec "apt-get update && apt-get install -y curl g++ make"
```

This keeps the core minimal and the choice explicit per target, rather than baking a prereq list into `dts`.

### Static mount target: `/src`

The repo is always bind-mounted at `/src`. Simple, predictable, one name. Targets reference `/src/...` in their commands.

### Non-goals (deliberate)

- **No test-definition / YAML schema.** Per-target logic is a plain bash function or a short script. If you can test something manually in three commands, the test is three lines of bash — not a manifest.
- **No `verify` subcommands.** Verification is shell: check exit codes, grep output, curl endpoints.
- **No Dockerfile.** Bind-mount + a base image. No image build, no rebuild cycle.
- **No persistent SSH-like daemon.** `docker exec -i` with piped stdin reproduces a stateful session; we don't need a server inside the container.
- **No bundled apt prereqs.** Install what you need at test time via `dts exec`.

### Naming

**Docker Test Shell**, command `dts`. Plain, descriptive, honest about what it is. Not "harness," not "framework."

## Key design decisions (each grounded in live testing)

| Decision | Validation |
|----------|-----------|
| Fresh base, never the host | Host state lies (stale packages/venvs/services) |
| Run as uid‑1000 `ubuntu` user, never root | CI runner + Codespace both run uid 1000; root masks permission bugs |
| Live bind-mount of the repo at `/src` | Verified bidirectional: host write appears in container, container write appears on host, files md5-identical both sides |
| TTY-aware exec: `-i` scripted, `-it` human | Verified: `-it` errors with "input device is not a TTY" when stdin is piped; `-i` runs scripted + stateful REPL-style commands fine |
| Login shell (`bash -l`) | `bash -c` is non-interactive and doesn't source `.profile`; parity with CI needs the login shell |
| Verify mount with md5, not listing | Listing can lie; md5 proves same file |
| Guaranteed cleanup | Orphan containers leak disk; CI doesn't clean up after you |

## How a future agent uses it

Core loop — edit on host, test in the container, repeat. No rebuild:

```bash
dts up                         # fresh container, repo mounted
dts exec "bash /src/install.sh"
dts exec "hermes --version"    # did it install?
# ... observe, edit a host file, re-run:
dts exec "bash /src/install.sh"   # mount makes the edit live immediately
dts clean                      # done, no orphan
```

A target becomes a short script of `dts exec` + bash checks. Another project ships its own ~10-line script reusing the same primitive.

## The teaching layer (why this becomes a skill too)

The design is the *how*; a skill is the *why* + method. A future agent needs to learn:

1. **Never trust the host** — always repro in a fresh container; host state lies.
2. **Drive with `docker exec -i`**, never `-it`, when scripted; reserve `-it` for a human TTY.
3. **Use `bash -l`** and the right uid (1000) for host/CI parity.
4. **Install apt packages manually** inside the container via `dts exec "apt-get update && apt-get install -y <pkgs>"` — don't bake them into the tool.
5. **Clean up** — no orphan containers.
6. **The root-cause mindset** — find why it fails in the clean env, don't weaken the test.

That's the skill's job; it lands in `.devcontainer/skills/` as procedural knowledge, and this wiki article references it.

## Shipping the code

The `dts` script ships **with the skill**, in `.devcontainer/skills/docker-test-shell/scripts/` (accessible via the `~/.hermes/skills/codespace` symlink). Any Codespace that loads the skill gets the tool. This keeps it self-contained and guarantees the skill and its executable stay in sync.

## See also

- [github-actions-testing-plan.md](github-actions-testing-plan.md) — CI is still the merge gate; `dts` is for fast local iteration

---

*Living proposal — update as design or testing clarifies.*