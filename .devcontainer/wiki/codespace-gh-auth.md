# GitHub Authentication in Codespaces

## Overview

In a GitHub Codespace, the `GITHUB_TOKEN` environment variable is set in the VS Code server process but NOT inherited by the Hermes agent session or other shell contexts. This creates a common authentication pitfall where `gh auth login` appears to work but actually uses an invalid token.

This article documents the reference architecture for extracting and using the real GitHub OAuth token in Codespaces.

### The Token Problem

#### Invalid Shell Tokens

Codespaces set these environment variables in the agent shell:
- `GH_TOKEN` — Often expired or scoped only to Codespace management
- `GITHUB_CODESPACE_TOKEN` — Limited scope, returns 401 for REST API calls

When `GH_TOKEN` is set to an invalid token, `gh auth login` silently refuses to work, claiming "The value of the GH_TOKEN environment variable is being used for authentication."

**This is the #1 auth blocker in Codespaces. Always check for it first.**

#### The Real Token Location

The VS Code server process (`server-main.js`) has a **GitHub App user-to-server token** (`ghu_xxx` prefix, ~40 chars) in its process environment at `/proc/PID/environ`.

The agent session does NOT inherit the VS Code server's environment — the real token lives in the server process and must be extracted explicitly.

#### Critical Limitation: GitHub App Token Scope

**The extracted token is a GitHub App token (from the GitHub Codespaces app), not a classic OAuth token.**

| Token Type | Format | Scope Restriction |
|------------|--------|-------------------|
| Extracted (GitHub App) | `ghu_...` | **Only works on repos where the GitHub Codespaces app is installed** (origin repo + forks of it) |
| Device Flow (Classic OAuth) | `gho_...` / `ghp_...` | **All repos the user has access to** |

The extracted token shows `X-Accepted-OAuth-Scopes: repo` but has **empty `X-OAuth-Scopes`** — it's gated by GitHub App installation. It will fail with `403 Resource not accessible by integration` on repos where the Codespaces app isn't installed (e.g., repos under a different user account without Codespaces enabled).

**Use the extracted token for:** The Codespace's origin repo and its forks.
**Use the device flow for:** Any other repo (different owner, private repos without Codespaces app).

**Critical limitation**: This token is a **GitHub App token** (from the GitHub Codespaces app).
It has `repo` scope but is **gated by GitHub App installation**. It works for:
- The Codespace's origin repository
- Other repositories where the GitHub Codespaces app is installed

It will **FAIL (403)** on repositories where the user has access but the Codespaces app is not installed.

## Token Extraction

### Step 1: Find VS Code Server PID

```bash
VSCODE_PID=$(pgrep -f "server-main.js" | head -1)
```

**Pitfall**: Multiple `server-main.js` processes may exist. The main server runs `server-main.js` directly (not `bootstrap-fork` children). If extraction returns empty, try each PID:

```bash
for pid in $(pgrep -f "server-main.js"); do
  TOKEN=$(cat /proc/$pid/environ 2>/dev/null | tr '\0' '\n' | grep "^GITHUB_TOKEN=" | cut -d= -f2-)
  [ -n "$TOKEN" ] && echo "Found token in PID $pid" && break
done
```

### Step 2: Extract GITHUB_TOKEN

```bash
GITHUB_TOKEN=$(cat /proc/$VSCODE_PID/environ 2>/dev/null \
  | tr '\0' '\n' \
  | grep "^GITHUB_TOKEN=" \
  | cut -d= -f2-)
```

### Step 3: Verify Token Works

```bash
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/user | python3 -c "import json,sys; print(json.load(sys.stdin).get('login','FAILED'))"
```

## Using the Token

### For Direct API Calls

```bash
curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/OWNER/REPO/issues/ISSUE_NUM/comments" \
  -d '{"body": "your comment"}'
```

### For gh CLI

```bash
unset GH_TOKEN
export GH_TOKEN="$GITHUB_TOKEN"
gh auth status  # Should show authenticated
```

The token gives you the same permissions as the user who opened the Codespace.

## Auth Detection Flow

```bash
# Quick check: does gh work for write operations?
if gh auth status 2>&1 | grep -q "Logged in"; then
  echo "OK: gh authenticated"
elif [ -n "$GH_TOKEN" ]; then
  echo "PROBLEM: GH_TOKEN is set but likely invalid"
  echo "FIX: unset GH_TOKEN && gh auth login --hostname github.com --git-protocol https --web"
else
  echo "NOT AUTHENTICATED"
  gh auth login --hostname github.com --git-protocol https --web
fi
```

## Fallback: Device Code Flow

If token extraction fails, use device code flow (works in any Codespace terminal):

```bash
unset GH_TOKEN
gh auth login --hostname github.com --git-protocol https --web
```

This prints a one-time code and URL. The user visits the URL and enters the code — one-time browser approval. No PAT creation needed.

**User preference**: Do not ask Codespace users to create PATs or run manual auth commands. The device code flow IS the expected auth path in a Codespace.

## VS Code IPC Credential Helper (Git Only)

Codespaces configure `git credential.helper` to use a VS Code IPC socket (`/.codespaces/bin/gitcredential_github.sh`). This works for `git push/pull/fetch` from within VS Code terminals but often fails from agent shell contexts because the IPC socket (`/tmp/vscode-git-*.sock`) is not reachable or returns 500.

**This is normal** — use token extraction or `gh auth login` instead.

## Git Push with Extracted Token (When IPC Fails)

```bash
VSCODE_PID=$(pgrep -f "server-main.js" | head -1)
GITHUB_TOKEN=$(cat /proc/$VSCODE_PID/environ 2>/dev/null | tr '\0' '\n' | grep "^GITHUB_TOKEN=" | cut -d= -f2-)

git config credential.helper store
echo "https://gitricko:${GITHUB_TOKEN}@github.com" > ~/.git-credentials
git push origin <branch>
```

## Related

- **Skill**: `.devcontainer/skills/codespace-gh-auth/` — Procedural how-to with git-push-with-token.md reference
- **Skill**: `.devcontainer/skills/github-codespace/` — Full Codespace workflow (auth, CI, PR)
- **Wiki**: [github-codespace.md](github-codespace.md) — Complete workflow including CI monitoring
- **Wiki**: [codespace-playbook.md](codespace-playbook.md) — Comprehensive Codespace operations guide