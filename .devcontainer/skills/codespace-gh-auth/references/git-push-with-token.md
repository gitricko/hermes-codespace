# Git Push with GITHUB_TOKEN in Codespaces

## Problem

Standard `git push` fails in Codespaces because:
- The HTTPS remote URL requires authentication
- The `GITHUB_TOKEN` from VS Code server is not available to the shell
- `gh auth login` is unnecessary (token already exists in VS Code server)

## Solution: Embed Token in Remote URL

```bash
# 1. Extract token from VS Code server (from codespace-gh-auth)
VSCODE_PID=$(pgrep -f "server-main.js" | head -1)
GITHUB_TOKEN=$(cat /proc/$VSCODE_PID/environ 2>/dev/null | tr '\0' '\n' | grep "^GITHUB_TOKEN=" | cut -d= -f2-)

# 2. Rewrite remote URL with token embedded
git remote set-url origin https://${GITHUB_TOKEN}@github.com/OWNER/REPO.git

# 3. Push works without credential prompts
git push origin BRANCH_NAME
```

## Alternative: Use GH_TOKEN for gh CLI

```bash
# For gh CLI commands (pr create, issue comment, etc.)
export GH_TOKEN="$GITHUB_TOKEN"
gh pr create --repo OWNER/REPO --head BRANCH --base main --title "Title" --body "Body"
```

## Complete Workflow: Create Branch → Push → PR

```bash
# 1. Extract token
VSCODE_PID=$(pgrep -f "server-main.js" | head -1)
GITHUB_TOKEN=$(cat /proc/$VSCODE_PID/environ 2>/dev/null | tr '\0' '\n' | grep "^GITHUB_TOKEN=" | cut -d= -f2-)

# 2. Set up git (if needed)
git config user.name "Your Name"
git config user.email "your@email.com"

# 3. Create branch, commit changes
git checkout -b feature-branch
git add .
git commit -m "feat: description"

# 4. Push with token-embedded URL
git remote set-url origin https://${GITHUB_TOKEN}@github.com/OWNER/REPO.git
git push origin feature-branch

# 5. Create PR via gh CLI
export GH_TOKEN="$GITHUB_TOKEN"
gh pr create --repo OWNER/REPO --head feature-branch --base main --title "Title" --body "Body"
```

## Notes

- Token is a `ghu_xxx` OAuth user token (~40 chars)
- Works for both public and private repos
- No need for `gh auth login` or SSH keys
- Token has same permissions as the user who opened the Codespace