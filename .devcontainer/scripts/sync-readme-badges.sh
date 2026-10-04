#!/usr/bin/env bash
# sync-readme-badges.sh — rewrite shields.io version pills in README.md from
# .devcontainer/post-create-cmd.sh (single source of truth).
# Mirrors .minions/scripts/sync-readme-badges.sh but without deps.yaml —
# the pin file is post-create-cmd.sh itself (same var() reader as check-deps.sh).
#
# Usage: bash .devcontainer/scripts/sync-readme-badges.sh [--check]
#   --check: exit 1 if README badges would differ (CI guard).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIN_FILE="${PIN_FILE:-${SCRIPT_DIR}/../post-create-cmd.sh}"
README="${README:-$(cd "${SCRIPT_DIR}/../.." && pwd)/README.md}"

if [ ! -f "${PIN_FILE}" ]; then
  echo "missing ${PIN_FILE}" >&2; exit 2
fi
if [ ! -f "${README}" ]; then
  echo "missing ${README}" >&2; exit 2
fi

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

# Reads NAME=value and strips surrounding quotes (matches check-deps.sh var()).
var() {
  sed -n "s/^$1=//p" "${PIN_FILE}" | head -1 | tr -d "\"'"
}

HERMES="$(var HERMES_VERSION)"
OMNIROUTE="$(var OMNIROUTE_VERSION)"
NINE_ROUTER="$(var NINE_ROUTER_VERSION)"
MNEMON="$(var MNEMON_VERSION)"
PI_AGENT="$(var PI_AGENT_VERSION)"

python3 - "${README}" "${CHECK}" "${HERMES}" "${OMNIROUTE}" "${NINE_ROUTER}" "${MNEMON}" "${PI_AGENT}" <<'PY'
import re, sys

readme_path, check_s, hermes, omniroute, ninerouter, mnemon, pi = sys.argv[1:8]
check = check_s == "1"
readme = open(readme_path).read()
orig = readme
drift = []

# label -> version as pinned (keep leading v when present, e.g. HERMES v2026.9.24)
LABELS = {
    "Hermes%20Agent": hermes,
    "PI%20Agent": pi,
    "9Router": ninerouter,
    "OmniRoute": omniroute,
    "Mnemon": mnemon,
}

for label, version in LABELS.items():
    if not version:
        print(f"  {label}: no pinned version, skipped", file=sys.stderr)
        continue
    # badge/<LABEL>-<version>-  -> replace the version segment
    pattern = re.compile(r"(badge/%s-)([^-]+)(-)" % re.escape(label))
    new_readme, n = pattern.subn(lambda m, v=version: m.group(1) + v + m.group(3), readme)
    if n == 0:
        print(f"  {label}: no badge found, skipped", file=sys.stderr)
        continue
    if new_readme != readme:
        drift.append((label, version))
    readme = new_readme

if check:
    if drift:
        for label, version in drift:
            print(f"  {label} badge should read {version}")
        print("README badges are out of date — run sync-readme-badges.sh", file=sys.stderr)
        sys.exit(1)
    print("README badges match post-create-cmd.sh")
else:
    for label, version in drift:
        print(f"  {label} badge -> {version}")
    if drift:
        open(readme_path, "w").write(readme)
PY
rc=$?
if [ "$CHECK" -eq 1 ]; then
  exit $rc
fi
# non-check mode: propagate python exit on error
exit $rc
