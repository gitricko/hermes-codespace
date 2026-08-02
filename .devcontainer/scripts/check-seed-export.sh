#!/bin/bash
# check-seed-export.sh — Check for new high-importance Mnemon entries
# that should be exported to seed.json before merging a PR.
#
# Usage: .devcontainer/scripts/check-seed-export.sh
# Exit code: 0 = no new entries, 1 = new entries found (action needed)

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
SEED_FILE="$WORKSPACE_ROOT/.devcontainer/mnemon/seed.json"

echo "=== Mnemon Seed Export Check ==="
echo ""

# Check prerequisites
if ! command -v mnemon &>/dev/null; then
  echo "ERROR: mnemon CLI not found"
  exit 1
fi

if [ ! -f "$SEED_FILE" ]; then
  echo "ERROR: Seed file not found: $SEED_FILE"
  exit 1
fi

# Query Mnemon for all entries, save to temp file
TMPFILE=$(mktemp /tmp/mnemon-export-XXXXXX.json)
mnemon recall "" --limit 100 --basic 2>/dev/null > "$TMPFILE"

if [ ! -s "$TMPFILE" ]; then
  echo "No Mnemon entries found."
  rm -f "$TMPFILE"
  exit 0
fi

# Compare against seed.json using Python
python3 - "$TMPFILE" "$SEED_FILE" << 'PYTHON_SCRIPT'
import json, sys

mnemon_file = sys.argv[1]
seed_file = sys.argv[2]

# Parse Mnemon entries
with open(mnemon_file) as f:
    mnemon_data = json.load(f)

# Handle both list and dict formats
if isinstance(mnemon_data, list):
    entries = mnemon_data
elif isinstance(mnemon_data, dict):
    entries = mnemon_data.get('insights', [])
else:
    entries = []

# Parse existing seed
try:
    with open(seed_file) as f:
        seed = json.load(f)
    seed_contents = {e['content'][:60] for e in seed.get('insights', [])}
except:
    seed_contents = set()

# Find new high-importance entries
new_entries = []
for e in entries:
    importance = e.get('importance', 0)
    content = e.get('content', '')
    if importance >= 4 and content[:60] not in seed_contents:
        new_entries.append(e)

if not new_entries:
    print('No new high-importance entries to export.')
    print(f'Seed file has {len(seed_contents)} existing entries.')
    sys.exit(0)

print(f'Found {len(new_entries)} new high-importance entries:')
print()
for i, e in enumerate(new_entries, 1):
    cat = e.get('category', 'general')
    imp = e.get('importance', '?')
    content = e.get('content', '')[:100]
    print(f'  {i}. [{imp}] ({cat}) {content}')
    if e.get('tags'):
        print(f'     Tags: {", ".join(e["tags"][:5])}')
    print()

print('ACTION: Review and add to seed.json before merging.')
print('  1. Run: mnemon recall "<topic>" --limit 5')
print('  2. Add to .devcontainer/mnemon/seed.json')
print('  3. Validate: mnemon import --dry-run .devcontainer/mnemon/seed.json')
print('  4. Commit and push')
sys.exit(1)
PYTHON_SCRIPT

RESULT=$?
rm -f "$TMPFILE"
exit $RESULT
