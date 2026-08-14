#!/usr/bin/env python3
"""
launch_slot.py — allocate a lavish-axi slot for a Hermes session and bring it online.

Steps:
  1. Allocate slot (engine port, public port, state dir) via slot_allocator.py
  2. Write nginx config for the public port (Origin rewrite + WebSocket upgrade)
  3. Reload nginx
  4. Start lavish-axi engine (background, loopback-only) in the slot state dir
  5. Expose the public port (gh codespace ports forward + visibility)
  6. Print the public session URL

The agent then runs the poll supervisor (poll_supervisor.py) in the slot state dir.

Usage:
  python3 launch_slot.py <hermes_session_id> <artifact_path> [lavish_axi_dir]
"""
import json
import os
import subprocess
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
HERE = os.path.dirname(SCRIPT_DIR)
EXPOSE_PORT = os.path.join(HERE, "..", "codespace-port-visibility", "scripts", "expose_port.py")
TEMPLATE = os.path.join(SCRIPT_DIR, "nginx_slot.template")
NGINX_ENABLED = "/etc/nginx/sites-enabled"
CODESPACE_NAME = os.environ.get("CODESPACE_NAME", "probable-waddle-q757j5pp649f9wvx")


def run(cmd, check=True):
    print(f"[launch_slot] {cmd}")
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if check and r.returncode != 0:
        print(f"[launch_slot] ERROR: {r.stderr}", file=sys.stderr)
        sys.exit(1)
    return r


def main():
    if len(sys.argv) < 3:
        print("usage: launch_slot.py <hermes_session_id> <artifact_path> [lavish_axi_dir]", file=sys.stderr)
        sys.exit(2)

    hermes_session_id = sys.argv[1]
    artifact_path = sys.argv[2]
    lavish_dir = sys.argv[3] if len(sys.argv) > 3 else "/workspaces/lavish-axi"

    # 1. Allocate slot
    rec = json.loads(subprocess.check_output(
        [sys.executable, os.path.join(SCRIPT_DIR, "slot_allocator.py"), "alloc", hermes_session_id, artifact_path]
    ))
    engine_port = rec["engine_port"]
    public_port = rec["public_port"]
    state_dir = rec["state_dir"]
    session_key = rec["session_key"]
    print(f"[launch_slot] slot {rec['slot']}: engine={engine_port} public={public_port} state={state_dir}")

    # 2. Write nginx config
    with open(TEMPLATE) as f:
        tpl = f.read()
    conf = tpl.format(engine_port=engine_port, public_port=public_port)
    conf_path = f"/tmp/lavish-slot{rec['slot']}.conf"
    with open(conf_path, "w") as f:
        f.write(conf)
    run(f"sudo ln -sf {conf_path} {NGINX_ENABLED}/lavish-axi-slot{rec['slot']}")
    run("sudo nginx -s reload")

    # 3. Start lavish-axi engine
    env = dict(os.environ)
    env["LAVISH_AXI_PORT"] = str(engine_port)
    env["LAVISH_AXI_STATE_DIR"] = state_dir
    env["LAVISH_AXI_NO_OPEN"] = "1"
    subprocess.Popen(
        f"node {lavish_dir}/dist/cli.mjs server --port {engine_port}",
        shell=True, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    # Wait for engine health
    for _ in range(20):
        r = run(f"curl -s http://127.0.0.1:{engine_port}/health", check=False)
        if "ok" in r.stdout:
            break
        time.sleep(0.5)
    else:
        print("[launch_slot] engine did not start", file=sys.stderr)
        sys.exit(1)

    # 4. Open the artifact session on this engine
    run(f"cd {lavish_dir} && LAVISH_AXI_PORT={engine_port} LAVISH_AXI_STATE_DIR={state_dir} node dist/cli.mjs {artifact_path} --no-open", check=False)

    # 5. Expose public port
    expose = os.path.abspath(EXPOSE_PORT)
    if os.path.exists(expose):
        # expose_port.py runs `gh forward` (a long-lived tunnel) in background,
        # then flips visibility. We wait for the tunnel to register, then ensure public.
        run(f"timeout 30 python3 {expose} {public_port}", check=False)
        # ensure visibility is public even if the script's final step was cut off
        run(f"gh codespace ports visibility {public_port}:public -c {CODESPACE_NAME}", check=False)

    public_url = f"https://{CODESPACE_NAME}-{public_port}.app.github.dev/session/{session_key}"
    print(json.dumps({"slot": rec["slot"], "engine_port": engine_port, "public_port": public_port,
                      "state_dir": state_dir, "session_key": session_key, "public_url": public_url}, indent=2))
    print(f"[launch_slot] PUBLIC URL: {public_url}")


if __name__ == "__main__":
    main()
