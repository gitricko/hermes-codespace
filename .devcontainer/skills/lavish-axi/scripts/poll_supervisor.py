#!/usr/bin/env python3
"""
poll_supervisor.py — keep a lavish-axi poll alive for a slot.

lavish-axi poll is a long-poll: it captures one feedback, returns, and exits.
This supervisor re-runs it after each cycle so the listener stays alive. The poll
MUST run with LAVISH_AXI_PORT matching the engine that owns the slot's state dir.

This script is meant to be launched as a tracked background process (harness
background=true, notify_on_complete=true). It runs forever; the harness kills it
when the session ends.

Usage:
  python3 poll_supervisor.py <slot_state_dir> <artifact_path> [engine_port]
"""
import os
import subprocess
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def main():
    if len(sys.argv) < 3:
        print("usage: poll_supervisor.py <slot_state_dir> <artifact_path> [engine_port]", file=sys.stderr)
        sys.exit(2)

    state_dir = sys.argv[1]
    artifact_path = sys.argv[2]
    engine_port = sys.argv[3] if len(sys.argv) > 3 else "4387"

    lavish_dir = os.environ.get("LAVISH_AXI_DIR", "/workspaces/lavish-axi")

    print(f"[poll_supervisor] state_dir={state_dir} artifact={artifact_path} engine={engine_port}")

    while True:
        env = dict(os.environ)
        env["LAVISH_AXI_PORT"] = str(engine_port)
        env["LAVISH_AXI_STATE_DIR"] = state_dir
        try:
            r = subprocess.run(
                f"cd {lavish_dir} && node dist/cli.mjs poll {artifact_path}",
                shell=True, env=env, capture_output=True, text=True, timeout=3600,
            )
            out = r.stdout + r.stderr
            if "status: feedback" in out or "feedback" in out:
                print(f"[poll_supervisor] captured feedback, restarting poll")
            elif "session ended" in out.lower() or "ended" in out.lower():
                print(f"[poll_supervisor] session ended, exiting")
                break
            else:
                # timeout or interrupted — restart silently
                pass
        except subprocess.TimeoutExpired:
            print(f"[poll_supervisor] poll timed out, restarting")
        except Exception as e:
            print(f"[poll_supervisor] error: {e}, restarting in 2s")
            time.sleep(2)


if __name__ == "__main__":
    main()
