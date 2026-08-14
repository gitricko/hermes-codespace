#!/usr/bin/env python3
"""
Expose a GitHub Codespace port publicly with zero manual clicks.
For ports VS Code has NOT auto-forwarded, this runs BOTH steps:
  1. gh codespace ports forward <port>:<local-port>  (registers tunnel)
  2. gh codespace ports visibility <port>:public     (flips visibility)

Usage: python3 expose_port.py <port> [local-port] [codespace]
  local-port defaults to port+10000 to avoid colliding with the service already
  listening on <port> (gh tries to bind the local side).
"""
import os
import sys
import subprocess

sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from get_codespace_token import set_github_token_env


def expose_port(port: int, local_port: int = None, codespace: str = None):
    set_github_token_env()
    if local_port is None:
        local_port = port + 10000
    if not codespace:
        codespace = os.environ.get("CODESPACE_NAME")
        if not codespace:
            raise RuntimeError("CODESPACE_NAME not set")

    # Step 1: forward (establish tunnel)
    fwd = subprocess.run(
        ["gh", "codespace", "ports", "forward", f"{port}:{local_port}", "-c", codespace],
        capture_output=True, text=True,
    )
    if fwd.returncode != 0:
        # If already forwarded, forward fails with bind error — that's fine, continue
        if "address already in use" not in fwd.stderr and "already" not in fwd.stderr.lower():
            print(f"forward note: {fwd.stderr.strip()}")

    # Step 2: visibility
    vis = subprocess.run(
        ["gh", "codespace", "ports", "visibility", f"{port}:public", "-c", codespace],
        capture_output=True, text=True,
    )
    if vis.returncode != 0:
        raise RuntimeError(f"visibility failed: {vis.stderr}")
    return True


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <port> [local-port] [codespace]")
        sys.exit(1)
    p = int(sys.argv[1])
    lp = int(sys.argv[2]) if len(sys.argv) > 2 else None
    cs = sys.argv[3] if len(sys.argv) > 3 else None
    expose_port(p, lp, cs)
    print(f"Port {p} exposed (forwarded + public)")
