#!/usr/bin/env python3
"""
lavish-axi slot allocator.

Manages ~/.lavish-axi/slots.json — a registry mapping Hermes session IDs to
lavish-axi engine ports / public nginx ports / state dirs. Each Hermes conversation
owns exactly one slot, so multiple parallel "iterate this in lavish" sessions never
collide on a fixed port.

Port scheme (matching suffixes for readability):
  engine (loopback): 4387 + (slot-1)   -> 4387, 4388, 4389, ...
  public (nginx):    9987 + (slot-1)   -> 9987, 9988, 9989, ...

Usage:
  python3 slot_allocator.py alloc <hermes_session_id> [artifact_path]
      -> prints JSON: {slot, engine_port, public_port, state_dir, artifact_path, session_key, created_at}
  python3 slot_allocator.py get <hermes_session_id>
      -> prints existing slot JSON or exits 1
  python3 slot_allocator.py list
      -> prints all slots as JSON array
  python3 slot_allocator.py release <hermes_session_id>
      -> removes the slot (does not kill processes)
"""
import json
import os
import sys
from datetime import datetime, timezone

REGISTRY = os.path.expanduser("~/.lavish-axi/slots.json")
BASE_ENGINE = 4388  # loopback-only, never exposed (4387 reserved for legacy/default)
BASE_PUBLIC = 9988  # nginx public port (matching suffix: 4388<->9988, 4389<->9989)


def _load():
    if not os.path.exists(REGISTRY):
        return {}
    try:
        with open(REGISTRY) as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return {}


def _save(data):
    os.makedirs(os.path.dirname(REGISTRY), exist_ok=True)
    with open(REGISTRY, "w") as f:
        json.dump(data, f, indent=2)


def _session_key(artifact_path):
    import hashlib
    import pathlib
    return hashlib.sha256(str(pathlib.Path(artifact_path).resolve()).encode()).hexdigest()[:16]


def alloc(hermes_session_id, artifact_path=None):
    data = _load()
    # Reuse existing slot for this Hermes session
    for slot_rec in data.values():
        if slot_rec.get("hermes_session_id") == hermes_session_id:
            if artifact_path:
                slot_rec["artifact_path"] = str(artifact_path)
                slot_rec["session_key"] = _session_key(artifact_path)
                _save(data)
            return slot_rec
    # Allocate next free slot number
    used_slots = {int(k) for k in data.keys() if k.isdigit()}
    slot = 1
    while slot in used_slots:
        slot += 1
    engine_port = BASE_ENGINE + (slot - 1)
    public_port = BASE_PUBLIC + (slot - 1)
    state_dir = os.path.expanduser(f"~/.lavish-axi/slot-{slot}")
    rec = {
        "slot": slot,
        "engine_port": engine_port,
        "public_port": public_port,
        "state_dir": state_dir,
        "hermes_session_id": hermes_session_id,
        "artifact_path": str(artifact_path) if artifact_path else None,
        "session_key": _session_key(artifact_path) if artifact_path else None,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    data[str(slot)] = rec
    _save(data)
    return rec


def get(hermes_session_id):
    data = _load()
    for slot_rec in data.values():
        if slot_rec.get("hermes_session_id") == hermes_session_id:
            return slot_rec
    return None


def list_slots():
    return list(_load().values())


def release(hermes_session_id):
    data = _load()
    for key, slot_rec in list(data.items()):
        if slot_rec.get("hermes_session_id") == hermes_session_id:
            del data[key]
    _save(data)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    if cmd == "alloc":
        if len(sys.argv) < 3:
            print("usage: slot_allocator.py alloc <hermes_session_id> [artifact_path]", file=sys.stderr)
            sys.exit(2)
        rec = alloc(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
        print(json.dumps(rec))
    elif cmd == "get":
        if len(sys.argv) < 3:
            print("usage: slot_allocator.py get <hermes_session_id>", file=sys.stderr)
            sys.exit(2)
        rec = get(sys.argv[2])
        if rec:
            print(json.dumps(rec))
        else:
            sys.exit(1)
    elif cmd == "list":
        print(json.dumps(list_slots(), indent=2))
    elif cmd == "release":
        if len(sys.argv) < 3:
            print("usage: slot_allocator.py release <hermes_session_id>", file=sys.stderr)
            sys.exit(2)
        release(sys.argv[2])
        print("released")
    else:
        print(f"unknown command: {cmd}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
