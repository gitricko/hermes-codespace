#!/usr/bin/env bash
set -euo pipefail

BASE_URL="http://localhost:7352"
COOKIE_FILE="$(mktemp)"
trap 'rm -f "$COOKIE_FILE"' EXIT

# Log in and save the session cookie
curl -fsS -c "$COOKIE_FILE" \
  -X POST "$BASE_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"password":"123456"}' | jq

# Disable dashboard login and API-key enforcement
curl -fsS -b "$COOKIE_FILE" \
  -X PATCH "$BASE_URL/api/settings" \
  -H "Content-Type: application/json" \
  -d '{"requireLogin":false,"requireApiKey":false}' | jq '{requireLogin,requireApiKey}'

# Delete the combo if it already exists
COMBO_ID="$(curl -fsS -b "$COOKIE_FILE" "$BASE_URL/api/combos" |
  jq -r '.combos[] | select(.name=="auto-fastest") | .id' | head -n 1)"

if [[ -n "$COMBO_ID" ]]; then
  curl -fsS -b "$COOKIE_FILE" \
    -X DELETE "$BASE_URL/api/combos/$COMBO_ID" | jq
fi

# Create auto-fastest with all free oc/ models
curl -fsS -b "$COOKIE_FILE" \
  -X POST "$BASE_URL/api/combos" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "auto-fastest",
    "models": [
      "oc/muse-spark-1.2-contributor-free",
      "oc/muse-spark-1.3-contributor-free",
      "oc/union-alpha",
      "oc/big-pickle",
      "oc/mimo-v2.5-free",
      "oc/nemotron-3-ultra-free",
      "oc/nemotron-3.5-lightning-free"
    ]
  }' | jq '{name,models}'

# Preserve other combo strategies and set auto-fastest to round-robin
STRATEGIES="$(
  curl -fsS -b "$COOKIE_FILE" "$BASE_URL/api/settings" |
  jq -c '
    (.comboStrategies // {})
    | .["auto-fastest"] = ((.["auto-fastest"] // {}) + {fallbackStrategy: "round-robin"})
  '
)"

curl -fsS -b "$COOKIE_FILE" \
  -X PATCH "$BASE_URL/api/settings" \
  -H "Content-Type: application/json" \
  -d "{\"comboStrategies\":$STRATEGIES}" | jq '.comboStrategies["auto-fastest"]'

# Test the combo
curl -fsS "$BASE_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "auto-fastest",
    "messages": [
      {"role": "user", "content": "Reply with exactly: OK"}
    ],
    "stream": false,
    "max_tokens": 16
  }' | jq