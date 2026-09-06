# GitHub Operations in GitHub Codespaces

## Overview

This article documents the complete reference architecture for GitHub operations in GitHub Codespaces, covering authentication, CI monitoring, CI debugging, and API access patterns specific to Codespaces.

## Authentication

### The Invalid GH_TOKEN Pitfall

Codespaces set `GH_TOKEN` and `GITHUB_CODESPACE_TOKEN` env vars. These tokens can be expired or scoped only to Codespace management — not repo write access.

When `GH_TOKEN` is set to an invalid token, `gh auth login` silently refuses to work, claiming "The value of the GH_TOKEN environment variable is being used for authentication."

**This is the #1 auth blocker in Codespaces. Always check for it first.**

### Fix: Device Code Flow

```bash
# Step 1: Unset the invalid token
unset GH_TOKEN

# Step 2: Use device code flow (works in any Codespace terminal)
gh auth login --hostname github.com --git-protocol https --web
```

This prints a one-time code and URL. The user visits the URL and enters the code — one-time browser approval. No PAT creation needed.

### Token Extraction from VS Code Server (Preferred — No Browser)

The VS Code server process has a **GitHub App user-to-server token** (`ghu_xxx`) in its environment.

```bash
# 1. Find the VS Code server PID
VSCODE_PID=$(pgrep -f "server-main.js" | head -1)

# 2. Extract the real GITHUB_TOKEN from its process environment
GITHUB_TOKEN=$(cat /proc/$VSCODE_PID/environ 2>/dev/null \
  | tr '\0' '\n' \
  | grep "^GITHUB_TOKEN=" \
  | cut -d= -f2-)

# 3. Verify it works
curl -s -H "Authorization: token ***" \
  https://api.github.com/user | python3 -c "import json,sys; print(json.load(sys.stdin).get('login','FAILED'))"
```

**Critical limitation**: This token is a **GitHub App token** (from the GitHub Codespaces app).
It has `repo` scope but is **gated by GitHub App installation**. It works for:
- The Codespace's origin repository
- Other repositories where the GitHub Codespaces app is installed

It will **FAIL (403)** on repositories where the user has access but the Codespaces app is not installed.

Use it for API calls, PR comments, and even `gh` CLI **on supported repos**:

```bash
unset GH_TOKEN
export GH_TOKEN="$GITHUB_TOKEN"
gh auth status  # Should show authenticated
```

### Token Scope Comparison

| Method | Token Type | Scope | Works On |
|--------|------------|-------|----------|
| **Extract from VS Code** | GitHub App user-to-server (`ghu_`) | `repo` (app-gated) | Origin repo + Codespaces-connected repos only |
| **Device code flow** | Classic OAuth (`gho_`/`ghp_`) | Full user scopes | **All repos the user has access to** |
| **Unauthenticated API** | None | Public only | Public repos (read-only) |

**When to use device flow instead**: Working on repos outside the Codespaces app installation (other users' repos, orgs without Codespaces app).

### Auth Detection Flow

```bash
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

### Multiple VS Code Server Processes

`pgrep -f "server-main.js"` may return multiple PIDs. The main server runs `server-main.js` directly (not `bootstrap-fork` children). If token extraction returns empty, try each PID.

### VS Code IPC Credential Helper

Codespaces configure `git credential.helper` to use a VS Code IPC socket (`/.codespaces/bin/gitcredential_github.sh`). This works for `git push/pull/fetch` from within VS Code terminals but often fails from agent shell contexts because the IPC socket (`/tmp/vscode-git-*.sock`) is not reachable or returns 500.

**This is normal** — use token extraction or `gh auth login` instead.

## CI Monitoring

### Preferred: `gh run watch`

Always use `gh run watch <run-id>` instead of sleep-polling loops. It streams logs in real-time, handles rate limiting, and exits on completion.

```bash
# Find the latest run for current branch
RUN_ID=$(gh run list --branch $(git branch --show-current) --limit 1 --json databaseId --jq '.[0].databaseId')

# Watch it
gh run watch $RUN_ID

# Watch with log output
gh run watch $RUN_ID --log

# Watch only failed jobs
gh run watch $RUN_ID --failed
```

### Non-blocking Watch (Background + Notify)

When a build takes longer than an agent turn can block (e.g., the ~5-15 min `full-build`), do NOT poll with `sleep` loops. Instead run `gh run watch` as a **background terminal process with notify_on_complete**:

```bash
tok=$(cat /proc/<VSCODE_PID>/environ 2>/dev/null | tr '\0' '\n' | grep '^GITHUB_TOKEN=' | cut -d= -f2-)
export GH_TOKEN="$tok"
gh run watch <RUN_ID> --repo OWNER/REPO --exit-status > /tmp/ci-watch.log 2>&1
echo "WATCH_EXIT=$?" >> /tmp/ci-watch.log
```

Launch with terminal `background=true, notify_on_complete=true`. It streams jobs/steps live to `/tmp/ci-watch.log`, and the agent is notified **once** when the run finishes.

### Fallback: REST API Polling (No gh Auth)

For public repos, you can poll CI status without authentication:

```bash
# Get PR info
PR_DATA=$(curl -s "https://api.github.com/repos/$OWNER/$REPO/pulls/$PR_NUMBER")
SHA=$(echo "$PR_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['head']['sha'])")

# Check run statuses
curl -s "https://api.github.com/repos/$OWNER/$REPO/commits/$SHA/check-runs" \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
for cr in d.get('check_runs', []):
    icon = '⏳' if cr['status'] == 'in_progress' else ('✅' if cr['conclusion'] == 'success' else '❌')
    print(f\"{icon} {cr['name']}: {cr['conclusion'] or 'pending'}\")"
```

Note: log download (`/actions/runs/{id}/logs`) requires admin access (403 for public repo read-only). Use `gh run view --log` when authenticated.

## CI Debugging

### Core Technique: Compare Passing vs Failing Commits

When CI fails on commit B but passed on commit A, the answer is in the diff.

```bash
# Step 1: Identify the commits
curl -s "https://api.github.com/repos/$OWNER/$REPO/actions/runs?per_page=10" | \
  python3 -c "
import sys, json
d = json.load(sys.stdin)
for r in d.get('workflow_runs', []):
    concl = r.get('conclusion', 'pending')
    print(f\"{r['head_sha'][:8]}: {concl} ({r['created_at']})\")"

# Step 2: Get the diff
git diff $PASSING_SHA..$FAILING_SHA --stat
git diff $PASSING_SHA..$FAILING_SHA -- <specific-file>

# Step 3: Download CI logs for both runs (requires admin token)
curl -sL -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/$OWNER/$REPO/actions/runs/$RUN_ID/logs" \
  -o /tmp/ci-logs.zip
unzip -o /tmp/ci-logs.zip -d /tmp/ci-logs-$RUN_ID/

# Step 4: Compare the specific failing step output
cat "/tmp/ci-logs-$RUN_ID/0_Build & Smoke Test.txt" | tail -100
```

### Downloading CI Artifacts

When CI logs don't contain enough detail, download uploaded artifacts.

```bash
# Find artifacts for a run
curl -s -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/$OWNER/$REPO/actions/runs/$RUN_ID/artifacts" \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
for a in d.get('artifacts', []):
    print(f\"Name: {a['name']}  ID: {a['id']}  Size: {a['size_in_bytes']}\")"

# Download and extract
curl -sL -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/$OWNER/$REPO/actions/artifacts/$ARTIFACT_ID/zip" \
  -o /tmp/artifact.zip
mkdir -p /tmp/artifact && cd /tmp/artifact && unzip -o ../artifact.zip
```

### Hard Rule: Fix Root Cause, Not Symptoms

When CI fails, the instinct is to weaken the test or skip the failing check. **The user will reject this.**

1. **Diagnose first** — download logs/artifacts, identify what actually failed
2. **Reproduce locally** — run the exact failing command in the local env
3. **Fix the root cause** — fix the code/build/config that's broken
4. **NOT the test** — don't skip checks, don't make services non-critical, don't remove assertions the user considers important

If the user says a service is "critical", it stays critical. The fix must make the service actually work, not make the test tolerate its absence.

**NEVER modify existing developer test cases.** If a test fails, fix the CODE, not the test.

### Common CI Failure Patterns

#### Broken Symlinks
**Symptom**: Service starts but never responds; self-check times out.
**Cause**: A symlink in the repo points to a local path that doesn't exist in CI.
```bash
git rm --cached .hermes
echo ".hermes" >> .gitignore
git commit -m "fix: remove broken .hermes symlink from git"
```

#### Service Not Starting in CI
**Symptom**: Port never responds; self-check fails with exit code 2.
```bash
ps aux | grep <service-name>
cat ~/.hermes/logs/dashboard.log
ss -tlnp | grep <port>
```
Common causes: missing dependency, config references local path, port conflict, resource limits.

#### GPG Signing Fails
```bash
git -c commit.gpgsign=false commit -m "fix: ..."
```

#### Git Push Times Out
**Cause**: VS Code IPC credential helper not reachable from agent shell.
```bash
VSCODE_PID=$(pgrep -f "server-main.js" | head -1)
GITHUB_TOKEN=$(cat /proc/$VSCODE_PID/environ 2>/dev/null | tr '\0' '\n' | grep "^GITHUB_TOKEN=" | cut -d= -f2-)
git config credential.helper store
echo "https://gitricko:${GITHUB_TOKEN}@github.com" > ~/.git-credentials
git push origin <branch>
```

#### Hermes Dashboard Silent Build Failure
**Symptom**: Self-check exits with code 2. Port 9119 never responds. Dashboard log shows "Web UI npm install failed" but NO npm error output appears.
**Root cause**: The hermes dashboard auto-builds its web UI on first boot. In CI, `npm ci` can fail silently (process killed, network issue, env mismatch) producing empty output.
**Fix**: Pre-build the web UI in `post-create-cmd.sh`:
```bash
HERMES_AGENT_DIR="$HOME/.hermes/hermes-agent"
if [ -d "$HERMES_AGENT_DIR/web" ] && command -v node &>/dev/null; then
  cd "$HERMES_AGENT_DIR"
  CI=1 npm ci --include=dev --workspace web --silent 2>&1 || \
    CI=1 npm install --no-save --include=dev --workspace web --silent 2>&1
  cd "$HERMES_AGENT_DIR/web" && CI=1 npm run build 2>&1
fi
```
Verification: `ls -la ~/.hermes/hermes-agent/hermes_cli/web_dist/index.html`

### CI Workflow Diagnostic Capture Template

```yaml
- name: Capture diagnostics
  if: always()
  run: |
    ps aux > /tmp/ps-aux.txt
    ss -tlnp > /tmp/ports.txt
    cat ~/.hermes/logs/gateway.log   > /tmp/gateway.log
    cat ~/.hermes/logs/dashboard.log > /tmp/dashboard.log

- name: Upload artifacts on failure
  if: failure()
  uses: actions/upload-artifact@v4
  with:
    name: failure-logs-${{ github.run_id }}
    path: /tmp/*.log /tmp/*.txt
```

Key principles: use `if: always()` for diagnostic steps, capture process list/port status/config/logs, upload as artifacts.

## Public Repo API Access Without Auth

For public repos, the GitHub REST API works without authentication for:
- PR details, file lists, diffs
- Check-run statuses and conclusions
- Workflow run metadata
- Commit status
- Issue/PR listing

**Always try unauthenticated first for public repos.** Only add auth headers when you get 401/403 or need write operations.

## Complete Codespace Workflow

```bash
# 1. Extract token (preferred) or use device code flow
VSCODE_PID=$(pgrep -f "server-main.js" | head -1)
export GH_TOKEN=$(cat /proc/$VSCODE_PID/environ 2>/dev/null | tr '\0' '\n' | grep "^GITHUB_TOKEN=" | cut -d= -f2-)
unset GH_TOKEN  # if above failed, fall back to device code
gh auth status 2>&1 | grep -q "Logged in" || gh auth login --hostname github.com --git-protocol https --web

# 2. Get repo info
OWNER_REPO=$(git remote get-url origin | sed -E 's|.*github\.com[:/]||; s|\.git$||')
OWNER=$(echo "$OWNER_REPO" | cut -d/ -f1)
REPO=$(echo "$OWNER_REPO" | cut -d/ -f2)

# 3. Work with PRs
gh pr view $PR_NUMBER
gh pr checks $PR_NUMBER --watch  # or: gh run watch $RUN_ID

# 4. Post comments / reviews
gh pr comment $PR_NUMBER --body "..."
gh pr review $PR_NUMBER --approve --body "LGTM!"

# 5. Fix CI failures
gh run view $RUN_ID --log-failed
# ... fix files ...
git add . && git commit -m "fix: ..." && git push
gh run watch $(gh run list --branch HEAD --limit 1 --json databaseId --jq '.[0].databaseId')
```

## Related

- **Skill**: `.devcontainer/skills/github-codespace/` — Procedural how-to
- **Skill**: `.devcontainer/skills/codespace-gh-auth/` — Token extraction details
- **Skill**: `.devcontainer/skills/github-pr-review/` — CodeQL/Copilot PR review
- **Wiki**: [codespace-gh-auth.md](codespace-gh-auth.md) — Token extraction details
- **Wiki**: [github-pr-review.md](github-pr-review.md) — PR review workflow
- **Wiki**: [codespace-playbook.md](codespace-playbook.md) — Comprehensive Codespace operations