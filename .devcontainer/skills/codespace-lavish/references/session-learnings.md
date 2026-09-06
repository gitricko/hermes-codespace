# Lavish Planning GUI — Session Learnings (2026-08-18)

## Ubuntu 24.04 Chromium Issue (Critical)

**Problem:** FR-1 in `Lavish-AXI-Merm.md` states `apt install chromium` works because "snap is unavailable in containers, so apt pulls the real deb." This is **false on Ubuntu 24.04 (noble)** — `chromium` is a snap-transitional stub with no apt candidate; `chromium-browser` is also a snap stub. Both fail on a fresh rebuild.

**Root cause:** Ubuntu 24.04 moved chromium entirely to snap. The transitional packages install nothing without snapd, which is unavailable in Codespace containers.

**Fix:** Install Google Chrome's official `.deb` directly:
```bash
curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -o /tmp/chrome.deb
apt-get install -y /tmp/chrome.deb
apt-mark manual google-chrome-stable   # protect from free-disk.sh autoremove
```
Then resolve browser at runtime: `google-chrome-stable || chromium || chromium-browser`.

**Files affected:**
- `lavish_planning_gui.sh` (browser resolution)
- `lavish_planning_prereqs.sh` (check 6 + --fix)
- Crewmate's `lavish-gui.sh` (already patched)
- `post-create-cmd.sh` (apt block in crewmate commit)

## pgrep -f Self-Match Pitfall

**Problem:** `pgrep -f "pattern"` matches the caller's own command line if the pattern appears in it, causing the shell to kill itself (SIGTERM).

**Examples that bit us:**
- `pkill -f "websockify.*6080"` — matched the kill command itself
- `pgrep -f "chrome-gui"` inside a loop — matched the loop's command line
- `pkill -f "lavish_planning_gui.sh"` — matched the foreground command

**Safe pattern:** Match by exact process name + filter via `/proc/<pid>/cmdline`:
```bash
MY=$$
for pid in $(pgrep -x chrome 2>/dev/null); do
  if grep -qa "user-data-dir=/tmp/chrome-gui" /proc/$pid/cmdline 2>/dev/null; then
    [ "$pid" != "$MY" ] && kill "$pid"
  fi
done
```
`pgrep -x chrome` only matches processes named exactly "chrome" (shell is "bash"), avoiding self-match. Then verify the distinctive flag in cmdline.

**Applied in:** `lavish_planning_gui.sh` (chrome cleanup), `lavish_planning_prereqs.sh` (no pgrep -f used).

## Lavish-AXI Feedback Loop Requires Poll

**Architecture:** Lavish is request/response. The server (`lavish-axi server`) serves the whiteboard at `/session/<key>`, but **user feedback (edits, comments) is queued and ONLY delivered when a `lavish-axi poll <artifact>` process is running.**

**Without poll:** User clicks in the whiteboard → feedback queued in Lavish → never delivered → whiteboard appears unresponsive.

**With poll:** Poll process long-polls `/session/<key>/poll`, receives feedback, prints it, and exits 0. Must be re-run for next cycle (or run continuously as we do).

**Our implementation:** `lavish_planning_gui.sh` starts poll in background:
```bash
( cd "$LAVISH_DIST" && LAVISH_AXI_PORT=... LAVISH_AXI_STATE_DIR=... \
  node "$LAVISH_DIST/cli.mjs" poll "$ARTIFACT" ) >/tmp/lavish-poll.log 2>&1 &
```
The poll PID is printed so the user can verify it's alive.

## Prerequisite Check Pattern (from firstmate_prereqs.sh)

**Style reference:** Upstream `firstmate_prereqs.sh` (hermes-firstmate-bridge) defines the pattern we replicated:

- Each check: `echo "[N] Name"`, then `ok()/bad()/fixed()/info()` with colored output
- `--fix` flag attempts install, converts FAIL→FIXED on success
- Fail-closed: any REQUIRED check FAIL → exit 1
- `set -u` (strict unset vars)
- Final summary: `ALL REQUIRED PREREQUISITES MET` (exit 0) or `N REQUIRED CHECK(S) FAILED` (exit 1)

**Our adaptation:** `lavish_planning_prereqs.sh` with 8 checks:
1. Xvfb
2. openbox
3. x11vnc
4. websockify
5. noVNC web assets
6. Browser binary (Chrome .deb on Ubuntu 24.04)
7. node + npm
8. lavish-axi (npx cache or on PATH)

**Key difference:** We don't assume sudo; try `sudo -n` first, fall back to direct apt (works in Codespace where we have nopasswd sudo).

## npx lavish-axi Resolution

**Pattern:** Lavish-AXI is not pre-installed. The skill resolves it on-demand:
```bash
if command -v lavish-axi >/dev/null; then
  LAVISH_DIST="$(dirname "$(command -v lavish-axi)")/../lib/node_modules/lavish-axi/dist"
else
  timeout 180 npx --yes lavish-axi --version >/dev/null 2>&1
  LAVISH_DIST="$(find ~/.npm/_npx -maxdepth 4 -type d -path '*lavish-axi/dist' | head -1)"
fi
```
This works in any Codespace with node/npm + network, zero pre-provisioning.

## Skill Structure Compliance (Hardline)

- Description ≤ 60 chars: "Launch a headed Lavish-AXI whiteboard viewable over noVNC." (59 chars)
- Frontmatter: name, description, version, author (human first), license, platforms, metadata.hermes.{tags, related_skills}
- Body sections: When to Use, Prerequisites, How to Run, Quick Reference, Procedure, Pitfalls, Verification
- All paths repo-relative (no machine-local)
- Commands framed via `terminal` tool in docs
- Each procedure step has checkable completion criterion

## Cross-Skill References

- `related_skills: [lavish-axi, codespace-port-visibility]`
- `lavish-axi` skill: slot orchestration, dynamic ports, poll_supervisor
- `codespace-port-visibility`: makes port 6080 PRIVATE (auth-gated)
- This skill adds the headed-GUI/noVNC layer on top of lavish-axi's engine

## Open Items for Next Session

- [ ] Commit `lavish-planning-gui` skill to repo (currently in `.devcontainer/skills/lavish-planning-gui/`)
- [ ] Consider whether to extend `lavish-axi` skill with the chromium fix pitfall (affects both skills)
- [ ] Test `--prompt "..."` artifact generation path end-to-end
- [ ] Verify CI path-filter treats `.devcontainer/skills/**` as content (lint-only) per CI rules

---

## 2026-08-19 Session Additions (codespace-lavish install & fix)

### Continuous Poll Loop with Auto-Restart

**Problem:** The `lavish-axi poll` process exits after delivering one batch of feedback. Without a loop, feedback after the first poll cycle is lost.

**Fix:** Wrap poll in a `while true` loop with 2s restart delay:
```bash
(
  cd "$LAVISH_DIST"
  while true; do
    LAVISH_AXI_PORT="$LAVISH_PORT" LAVISH_AXI_STATE_DIR="$STATE_DIR" \
      node "$LAVISH_DIST/cli.mjs" poll "$ARTIFACT" >>/tmp/lavish-poll.log 2>&1
    echo "[$(date)] poll exited, restarting in 2s..." >>/tmp/lavish-poll.log
    sleep 2
  done
) &
```

### `--monitor` Flag for Live Feedback

**Added:** New `--monitor` flag tails `/tmp/lavish-poll.log` after launch so the user sees feedback in real time:
```bash
bash lavish_planning_gui.sh --prompt "Plan X" --monitor
```

### Argument Parsing Fix for `--prompt`

**Bug:** Original argument parsing used a two-pass approach with a `_pending_prompt` variable that didn't work correctly — `--prompt "value"` resulted in the artifact path being set to "value" instead of generating from the prompt.

**Fix:** Single-pass loop with `((i++))` to consume the next argument:
```bash
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[i]}" in
    --prompt) PROMPT="${args[i+1]:-}"; ((i++)) ;;
    ...
  esac
done
```

### Node.js Session Key Derivation (Node 24+)

**Problem:** Node 24+ rejects destructured `require('crypto')` as `const c=require('crypto')` in `-e` eval context — throws `ERR_INVALID_ARG_TYPE: The "id" argument must be of type string. Received an instance of Object`.

**Fix:** Use full variable names:
```bash
SESSION_KEY=$(node -e "
  const crypto = require('crypto');
  const fs = require('fs');
  console.log(crypto.createHash('sha256').update(fs.realpathSync(process.argv[1])).digest('hex').slice(0,16))
" "$ARTIFACT")
```

### Skill Rename & Relocation

**Changed:** Skill renamed from `lavish-planning-gui` → `codespace-lavish` to match user's naming convention ("code space dash lavish"). Moved from `delme/codespace-lavish/` → `.devcontainer/skills/codespace-lavish/` with wiki article at `.devcontainer/wiki/codespace-lavish.md` and INDEX.md entry.

### Verification Updates

- Poll process auto-restarts: `pgrep -f "lavish-axi poll"` stays alive
- Poll log captures feedback: `/tmp/lavish-poll.log` receives entries continuously
- `--monitor` works: tails poll log live (Ctrl+C to exit)

### Chrome GPU Crash Fix (2026-08-19)

**Problem:** In Codespace containers (Ubuntu 24.04), Chrome's GPU process crashes with exit_code=15, leading to "GPU process isn't usable. Goodbye." fatal error. The `--disable-gpu` flag alone is insufficient — Chrome still spawns a GPU process that crashes.

**Root cause:** Container environment lacks GPU hardware/drivers; SwiftShader software renderer works but must be explicitly selected and GPU sandbox/compositing disabled.

**Fix:** Pass full software-rendering flags to Chrome:
```bash
--disable-gpu-sandbox --disable-gpu-compositing --disable-accelerated-2d-canvas \
--disable-accelerated-video-decode --disable-webgl --use-gl=swiftshader
```
Added to `lavish_planning_gui.sh` Chrome launch command. Verified Chrome stays running without GPU fatal error.

### noVNC Auto-Connect + Scaling (2026-08-19)

**Feature:** noVNC supports query string/hash configuration via `WebUtil.getConfigVar()`.

**Parameters:**
- `autoconnect=true` — auto-connects to VNC server on page load (skips "Connect" button)
- `resize=scale` — enables local scaling mode (viewport scales to fit browser window)

**URL format:**
```
https://<codespace>-6080.app.github.dev/vnc.html?autoconnect=true&resize=scale
```

**Verification:** 
- `curl 127.0.0.1:6080/vnc.html?autoconnect=true&resize=scale` returns 200
- noVNC HTML contains `<option value="scale">Local Scaling</option>` selected via JS
- Page loads directly to whiteboard without connect click

### Poll Process Survival & Disown Fix (2026-08-19)

**Problem:** The disowned background poll loop (`disown $POLL_PID`) was dying when the launching script/shell exited, even though it was wrapped in a `while true` loop with auto-restart. The `disown` without `-h` only removes from shell's job table but doesn't mark as no-hup.

**Fix:** Changed to `disown -h $POLL_PID 2>/dev/null || true` which marks the process with SIGHUP immunity (no-hup). The while-true loop also restarts on any exit with 2s delay. For maximum persistence, consider starting the poll as a separate tracked background job if the harness supports it (e.g., `terminal(background=true, notify_on_complete=true)`).

**Observed behavior:** The poll process stayed alive when the script ran interactively but died when launched via terminal tool that returned immediately. The `disown -h` + while-true combo appears to solve it.

### Argument Parsing Fix for `--prompt` (2026-08-19)

**Bug:** Original argument parsing used a two-pass approach with a `_pending_prompt` variable that didn't work correctly — `--prompt "value"` resulted in the artifact path being set to "value" instead of generating from the prompt.

**Fix:** Single-pass loop with `((i++))` to consume the next argument:
```bash
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[i]}" in
    --prompt) PROMPT="${args[i+1]:-}"; ((i++)) ;;
    ...
  esac
done
```

This is a general shell pattern for flag+value parsing that avoids the pending-variable bug.

### Agent Reply Spinner (2026-08-19)

**Observation:** The `poll --agent-reply` command delivers the agent's reply then continues long-polling for more feedback, showing a "working" spinner in the Lavish UI. This is **expected behavior** — the spinner does NOT block chat input; users can still type and send messages while it's visible.

**Background poll loop** (the script's `while true; do poll; done` without `--agent-reply`) runs without a spinner. Only the explicit reply command shows the spinner temporarily.

**Implication:** When sending agent replies, the spinner appears for a few seconds. This is not a bug — it's the poll command staying alive to wait for the next feedback batch.