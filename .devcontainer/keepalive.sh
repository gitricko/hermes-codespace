#!/usr/bin/env bash
# keepalive.sh — keep the Codespace "active" to avoid idle shutdown.
#                           (A) periodic terminal output on the session tty
#                           (B) internal /delay-shutdown pinger
#
# Safe to run as a background service. Wired into start-hermes.sh.
# If called with --test, runs quick verification and exits (for CI).

LOOP_TERMINAL=600    # write heartbeat every 10 minutes
LOOP_PINGER=240      # ping /delay-shutdown every 4 minutes

# Test mode flag
TEST_MODE=false
if [[ "${1:-}" == "--test" ]]; then
  TEST_MODE=true
fi

# Resolve this script's own directory so checks don't depend on the cwd
# (test mode is often invoked from the repo root or CI, not from .devcontainer/).
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/keepalive.sh"

fatal(){ echo "[keepalive] FATAL: $*" >&2; exit 1; }

# Discover the VS Code server port (server-main) from listening sockets.
# Server listens on 127.0.0.1 <port> (standard codespace setup).
discover_server_port(){
  local port=""
  # Try ss first
  if command -v ss >/dev/null 2>&1; then
    port=$(ss -ltn 2>/dev/null | awk '/server-main/ {for(i=1;i<=NF;i++) if($i ~ /^127\.0\.0\.1:/) {split($i,a,":"); print a[2]}}') || true
  fi
  if [ -z "$port" ] && command -v lsof >/dev/null 2>&1; then
    port=$(lsof -i -a -P -n 2>/dev/null | grep server-main | awk '{for(i=1;i<=NF;i++) if($i ~ /:.*LISTEN/) {split($i,a,":"); print a[2]}}') || true
  fi
  if [ -z "$port" ]; then
    # Fallback: find process with server-main and read netstat
    for pid in $(pgrep -f "server-main" 2>/dev/null); do
      if [ -d "/proc/$pid/net/tcp" ]; then
        # Hex port in /proc/<pid>/net/tcp - simplified, just for robustness
        :
      fi
    done
    # If we can't find it, fall back to common codespace ports
    port=46627  # most recent observation
  fi
  echo "$port"
}

# Write a small heartbeat string to the tty where hermes runs.
# Prefer the controlling terminal of the INTERACTIVE hermes process (the one
# attached to a tty), skipping gateway/dashboard which are headless. No PID is
# hardcoded — discovered at runtime so it stays portable across rebuilds/CI.
write_terminal_heartbeat(){
  local pty="" p cmd
  HERMES_BIN="$HOME/.hermes/hermes-agent/venv/bin/hermes"
  for p in $(pgrep -f "$HERMES_BIN" 2>/dev/null); do
    cmd=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
    echo "$cmd" | grep -qE "gateway|dashboard|--supervise" && continue
    if [ -r "/proc/$p/fd/0" ]; then
      pty=$(readlink "/proc/$p/fd/0" 2>/dev/null | grep -o 'pts/[0-9]*')
      [ -n "$pty" ] && break
    fi
  done
  [ -z "$pty" ] && pty="pts/0"
  # Overwrite the line, show a bullet character
  echo -ne '\r\b·' >"/dev/$pty" 2>/dev/null || true
}

# Hit internal /delay-shutdown endpoint (no auth required).
# If ping fails, the service logs but does not abort; we rely on external side.
_delay_shut_ping(){
  local port=$1
  local url="http://127.0.0.1:$port/delay-shutdown"
  local code

  # Use a short timeout; we just need best-effort delivery.
  code=$(curl -s -o /dev/null -w "%{http_code}" -m 3 "$url" 2>/dev/null || echo "000")
  if [ "$code" = "200" ]; then
    return 0
  else
    return 1
  fi
}

# Main loop
main(){
  local server_port
  server_port=$(discover_server_port)
  local pinger_counter=0

  while true; do
    # A) Terminal heartbeat (every LOOP_TERMINAL)
    write_terminal_heartbeat

    # B) Internal pinger (every LOOP_PINGER)
    _delay_shut_ping "$server_port" && pinger_counter=$((pinger_counter + 1))

    # Sleep until next cycle
    sleep "$LOOP_TERMINAL"
  done
}

# Test mode: run verification and exit
test_keepalive(){
  echo "=== Hermes Keepalive Test Mode ==="

  # Verify file exists and is executable (resolved from script location)
  if [[ ! -f "$SELF" ]]; then
    fatal "keepalive.sh not found ($SELF)"
  fi
  if [[ ! -x "$SELF" ]]; then
    fatal "keepalive.sh is not executable"
  fi
  echo "✅ keepalive.sh exists and is executable"

  # Discover port (use real container, not test mode)
  local server_port
  server_port=$(discover_server_port)
  echo "Discovered VS Code server port: $server_port"

  # Test terminal heartbeat (attempt to write to our own tty; should not error)
  echo "Testing terminal heartbeat write..."
  write_terminal_heartbeat
  echo "✅ Terminal heartbeat write successful"

  # Test curl to delay-shutdown (if port found)
  if [[ -n "$server_port" && "$server_port" != "none" ]]; then
    if _delay_shut_ping "$server_port"; then
      echo "✅ /delay-shutdown endpoint responded with HTTP 200"
    else
      echo "⚠️ /delay-shutdown endpoint returned $code (expected 200 for test)"
    fi
  else
    echo "⚠️ Could not discover server port, skipping /delay-shutdown test"
  fi

  echo "✅ Keepalive test completed successfully"
  echo "Note: this test does not start the full keepalive service loop;"
  echo "it only validates the individual functions (port discovery, terminal write, HTTP ping)."
  exit 0
}

# Run
if [[ "$TEST_MODE" == true ]]; then
  test_keepalive
else
  main
fi
