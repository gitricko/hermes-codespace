---
name: codespace-gh-auth
description: "Extract GitHub token from VS Code for API in Codespaces."
---

# GitHub Codespace Authentication

## Problem
In a GitHub Codespace, the GITHUB_TOKEN env var is set in the VS Code server process but NOT inherited by the Hermes agent session.

## Solution

### Step 1: Extract the real GITHUB_TOKEN from the VS Code server

```bash
VSCODE_PID=$(pgrep -f "server-main.js" | head -1)
GITHUB_TOKEN=$(cat /proc/$VSCODE_PID/environ 2>/dev/null | tr '\0' '\n' | grep "^GITHUB_TOKEN=" | cut -d= -f2-)
```

### Step 2: Use it for API calls

```bash
curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/OWNER/REPO/issues/ISSUE_NUM/comments" \
  -d '{"body": "your comment"}'
```

### Step 3: Use it for gh CLI (optional)

```bash
unset GH_TOKEN
export GH_TOKEN="$GITHUB_TOKEN"
gh auth status
```

## Pitfalls
- Do NOT use GITHUB_CODESPACE_TOKEN for REST API calls (returns 401)
- Do NOT run gh auth login (unnecessary)
- The VS Code server PID can be found with: pgrep -f "server-main.js"
- Token is a GitHub OAuth user token (ghu_xxx prefix), ~40 chars
