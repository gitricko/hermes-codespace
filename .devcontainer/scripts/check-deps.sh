#!/bin/bash
# Dependency version checker for Hermes CodeSpace.
# Compares versions pinned in .devcontainer/post-create-cmd.sh (single source of
# truth for the pinned set) against npm registry / GitHub tags / nodejs.org.
# Tools that are NOT pinned in the repo (node, ollama, code-server) are read
# from the running container instead.
#
# Usage: bash .devcontainer/scripts/check-deps.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIN_FILE="${SCRIPT_DIR}/../post-create-cmd.sh"

if [ ! -f "${PIN_FILE}" ]; then
  echo "ERROR: pin file not found: ${PIN_FILE}" >&2
  exit 2
fi

# --- GitHub API auth: unauthenticated limit is 60/hr per egress IP (shared) ---
# Prefer the Codespace's GitHub App token (ghu_) from the VS Code server env;
# falls back to $GITHUB_TOKEN/$GH_TOKEN if already exported. Raises limit to 5k-50k.
_github_token() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then echo "${GITHUB_TOKEN}"; return 0; fi
  if [ -n "${GH_TOKEN:-}" ]; then echo "${GH_TOKEN}"; return 0; fi
  local pid tok
  for pid in $(pgrep -f "server-main.js" 2>/dev/null); do
    tok=$(tr '\0' '\n' < "/proc/${pid}/environ" 2>/dev/null | sed -n 's/^GITHUB_TOKEN=//p')
    [ -n "${tok}" ] && { echo "${tok}"; return 0; }
  done
  return 1
}
GITHUB_TOKEN="$(_github_token 2>/dev/null || true)"
if [ -n "${GITHUB_TOKEN}" ]; then
  GH_AUTH_HEADER="Authorization: Bearer ${GITHUB_TOKEN}"
else
  GH_AUTH_HEADER=""
fi

# --- pinned versions: read from post-create-cmd.sh assignments, never hardcode here ---
# Matches both NAME=value and NAME="value" / NAME='value'.
var() {
  sed -n "s/^$1=//p" "${PIN_FILE}" | head -1 | tr -d "\"'"
}

# --- versions for tools that are NOT pinned in the repo ---
runtime() {  # $1 = tool name -> installed version, empty if not installed
  case "$1" in
    node)        command -v node        >/dev/null 2>&1 && node --version 2>/dev/null ;;
    ollama)      command -v ollama      >/dev/null 2>&1 && ollama --version 2>/dev/null | awk '{print $NF}' ;;
    code-server) command -v code-server >/dev/null 2>&1 && code-server --version 2>/dev/null | head -1 ;;
    *)           return 1 ;;
  esac
}

# --- current pinned versions (post-create-cmd.sh) ---
HERMES_VERSION="$(var HERMES_VERSION | sed 's/^v//')"
NINEROUTER_VERSION="$(var NINE_ROUTER_VERSION)"
OMNIROUTE_VERSION="$(var OMNIROUTE_VERSION)"
PI_VERSION="$(var PI_AGENT_VERSION)"
MNEMON_VERSION="$(var MNEMON_VERSION)"
HERDR_VERSION="$(var HERDR_VERSION)"

# --- current versions for tools detected at runtime ---
# "|| true": runtime() returns non-zero when the tool is absent, and set -e would
# otherwise abort the whole run just because one tool is not installed.
NODE_VERSION="$(runtime node || true)";       NODE_VERSION="${NODE_VERSION#v}"
OLLAMA_VERSION="$(runtime ollama || true)"
CODE_SERVER_VERSION="$(runtime code-server || true)"

# --- latest-version sources ---
npm_latest() {  # $1 = npm package name
  curl -fsSL "https://registry.npmjs.org/$1/latest" \
      | python3 -c "import json,sys; print(json.load(sys.stdin).get('version','?'))" 2>/dev/null \
      || echo "?"
}

gh_latest() {  # $1 = owner/repo -> newest stable tag (rc/beta/alpha/dev excluded, leading v stripped)
  local latest=""
  # Primary: GitHub REST API (authenticated via GH_AUTH_HEADER when available;
  # unauthenticated is only 60 req/hr per egress IP and often exhausted).
  # -L follows renames, -H sets required headers, -f makes curl fail on 403/404.
  if [ -n "${GH_AUTH_HEADER}" ]; then
    latest="$(curl -fsSL -H "${GH_AUTH_HEADER}" -H "User-Agent: Hermes" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$1/tags" 2>/dev/null \
      | python3 -c "
import json,sys,re
d = json.load(sys.stdin)
if not isinstance(d, list) or not d:
    print('?'); sys.exit()
pre = re.compile(r'(?i)(rc|beta|alpha|preview|pre[-.]|dev|nightly|canary|next)')
stable = [t['name'] for t in d if not pre.search(t['name'])]
print(stable[0].lstrip('v') if stable else '?')" 2>/dev/null || true)"
  fi
  # Fallback: git ls-remote skips the REST API entirely (separate rate limit).
  # Tags come as "sha<TAB>refs/tags/<tag>"; strip ^{} deref lines, sort -V.
  if [ -z "${latest}" ] || [ "${latest}" = "?" ]; then
    latest="$(git ls-remote --tags --refs "https://github.com/$1" 2>/dev/null \
      | awk '{print $2}' | sed 's|^refs/tags/||' \
      | grep -viE '(rc|beta|alpha|preview|pre[-.]?|dev|nightly|canary|next|premerge)' \
      | sed 's/^v//' | sort -V | tail -1 || true)"
  fi
  echo "${latest:-?}"
}

node_latest() {  # $1 = current version -> newest in the same major line
  case "$1" in
    [0-9]*) : ;;
    *) echo "?"; return 0 ;;   # no/unknown version -> nothing to compare against
  esac
  curl -fsSL "https://nodejs.org/dist/index.json" \
      | python3 -c "
import json,sys
major = sys.argv[1].split('.')[0]
d = json.load(sys.stdin)
vs = [x['version'].lstrip('v') for x in d if x['version'].startswith('v'+major+'.')]
def key(v):
    try: return [int(p) for p in v.split('.')]
    except ValueError: return [-1]
print(max(vs, key=key) if vs else '?')" "$1" 2>/dev/null \
      || echo "?"
}

check() {  # $1 = name, $2 = current, $3 = latest
  if [ -z "$2" ]; then
    printf '  %-18s current=NOT PINNED/INSTALLED | latest=%s\n' "$1" "$3"
    MISSING=$((MISSING + 1))
  elif [ "$3" = "?" ]; then
    printf '  %-18s current=%s | latest=UNAVAILABLE\n' "$1" "$2"
    UNAVAILABLE=$((UNAVAILABLE + 1))
  elif [ "$3" != "$2" ]; then
    printf '  %-18s current=%s | latest=%s [UPDATE AVAILABLE]\n' "$1" "$2" "$3"
    OUTDATED=$((OUTDATED + 1))
  else
    printf '  %-18s current=%s | latest=%s [OK]\n' "$1" "$2" "$3"
  fi
}

OUTDATED=0; UNAVAILABLE=0; MISSING=0

echo "=== Hermes Webtop Dependency Check ==="
echo "(pinned: .devcontainer/post-create-cmd.sh | node/ollama/code-server: detected at runtime)"
echo ""
echo "Pinned in post-create-cmd.sh — NPM packages:"
check "9router"         "${NINEROUTER_VERSION}"   "$(npm_latest 9router)"
check "omniroute"       "${OMNIROUTE_VERSION}"    "$(npm_latest omniroute)"
check "pi-coding-agent" "${PI_VERSION}"           "$(npm_latest @earendil-works/pi-coding-agent)"
echo ""
echo "Pinned in post-create-cmd.sh — GitHub-release binaries:"
check "hermes-agent"    "${HERMES_VERSION}"       "$(gh_latest NousResearch/hermes-agent)"
check "mnemon"          "${MNEMON_VERSION}"       "$(gh_latest mnemon-dev/mnemon)"
check "herdr"           "${HERDR_VERSION}"        "$(gh_latest ogulcancelik/herdr)"
echo ""
echo "Not pinned in repo — detected at runtime:"
check "node"            "${NODE_VERSION}"         "$(node_latest "${NODE_VERSION}")"
check "ollama"          "${OLLAMA_VERSION}"       "$(gh_latest ollama/ollama)"
check "code-server"     "${CODE_SERVER_VERSION}"  "$(gh_latest coder/code-server)"
echo ""

if [ "$OUTDATED" -eq 0 ] && [ "$UNAVAILABLE" -eq 0 ] && [ "$MISSING" -eq 0 ]; then
  echo "Summary: all dependencies up to date."
else
  echo "Summary: ${OUTDATED} update(s) available, ${UNAVAILABLE} lookup(s) unavailable, ${MISSING} not pinned/installed."
fi
