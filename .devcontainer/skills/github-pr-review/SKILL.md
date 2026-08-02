---
name: github-pr-review
description: "Evaluate GitHub CodeQL and Copilot suggestions on PRs — fetch, triage, propose fixes."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [GitHub, PR, CodeQL, Copilot, Review, Security, Code Quality]
    related_skills: [github-codespace, github-code-review]
---

# GitHub PR Review: CodeQL & Copilot Suggestions

Evaluates automated review comments from GitHub Advanced Security (CodeQL)
and GitHub Copilot on pull requests. Fetches comments, triages by severity,
and proposes fixes with a decision framework.

## Prerequisites

- GitHub API access (token via `/proc/PID/environ` or `gh auth`)
- PR number or URL

## Workflow

### Step 1: Fetch Review Comments

```bash
# Get PR review comments (CodeQL + Copilot inline comments)
curl -s "https://api.github.com/repos/{owner}/{repo}/pulls/{PR}/comments" \
  -H "Authorization: token $TOKEN" | python3 -c "
import json, sys
comments = json.load(sys.stdin)
for c in comments:
    author = c.get('user', {}).get('login', '?')
    if 'advanced-security' in author or 'copilot' in author:
        print(f'---')
        print(f'File: {c.get(\"path\", \"?\")}')
        print(f'Line: {c.get(\"line\", \"?\")}')
        print(f'Author: {author}')
        print(f'Body: {c.get(\"body\", \"\")[:500]}')
"
```

### Step 2: Triage by Source

| Source | What It Checks | Typical Findings |
|--------|---------------|------------------|
| `github-advanced-security[bot]` | CodeQL static analysis | Security vulnerabilities, workflow permissions, injection risks |
| `Copilot` | Code quality suggestions | Inconsistent naming, dead code, style issues |
| `copilot-pull-request-reviewer` | PR-level review | Logic errors, missing tests, documentation |

### Step 3: Evaluate Each Suggestion

For each comment, apply this decision framework:

#### ACCEPT if:
- Security issue (CodeQL finding) → always accept or explicitly justify rejection
- Workflow permission too broad → add `permissions:` block
- Actual bug or logic error → fix the code
- Inconsistent naming/branding → fix (e.g., wrong logo on badge)

#### REJECT if:
- False positive (CodeQL misidentification) → document why
- Style preference only (no functional impact) → note but skip
- Would break existing behavior without clear benefit → reject
- Suggestion is overly aggressive (e.g., "rename all variables") → reject

#### DEFER if:
- Requires architectural change → propose in separate PR
- Needs user decision → present options, wait for approval
- Unclear impact → investigate further before acting

### Step 4: Present Proposal

Format as a table for user review:

```
=== CodeQL & Copilot Review: PR #N ===

| # | Severity | Source | File | Suggestion | Proposal | Effort |
|---|----------|--------|------|------------|----------|--------|
| 1 | High     | CodeQL | workflow.yml | Missing permissions block | ACCEPT — add permissions: contents: read | 2 lines |
| 2 | Low      | Copilot | README.md | Wrong badge logo | ACCEPT — fix logo parameter | 1 line |
| 3 | Medium   | CodeQL | script.sh | Unquoted variable | REJECT — variable is intentionally word-split | 0 lines |

Summary: 2 accept, 1 reject, 0 defer
```

### Step 5: Implement Accepted Fixes

After user approval:
1. Make the changes
2. Commit with descriptive message
3. Push and verify CI passes
4. Optionally reply to the review comment with the fix

## API Endpoints

| Endpoint | Purpose |
|----------|---------|
| `GET /repos/{owner}/{repo}/pulls/{PR}/comments` | Inline review comments |
| `GET /repos/{owner}/{repo}/issues/{PR}/comments` | Top-level PR comments |
| `GET /repos/{owner}/{repo}/pulls/{PR}/reviews` | Full review objects |
| `POST /repos/{owner}/{repo}/pulls/{PR}/comments/{ID}/replies` | Reply to a comment |

## Common CodeQL Findings

### Workflow Permissions
```yaml
# BEFORE (triggers CodeQL warning)
name: CI
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps: [...]

# AFTER (fixes CodeQL warning)
name: CI
on: [push]
permissions:
  contents: read
jobs:
  build:
    runs-on: ubuntu-latest
    steps: [...]
```

### Script Injection
```yaml
# BEFORE (vulnerable)
- run: echo "${{ github.event.issue.body }}"

# AFTER (safe)
- run: echo "$ISSUE_BODY"
  env:
    ISSUE_BODY: ${{ github.event.issue.body }}
```

### Hardcoded Secrets
```yaml
# BEFORE (exposed)
env:
  API_KEY: sk-abc123...

# AFTER (use secrets)
env:
  API_KEY: ${{ secrets.API_KEY }}
```

## Common Copilot Findings

- **Inconsistent naming**: Badge uses wrong logo, variable name mismatches
- **Dead code**: Unused imports, unreachable branches
- **Missing error handling**: Unchecked return values
- **Style**: Inconsistent formatting, missing documentation

## Pitfalls

1. **Don't auto-apply all suggestions** — CodeQL can have false positives
2. **Don't fix style issues in functional code changes** — keep PRs focused
3. **Don't ignore security findings** — even if you reject, document why
4. **Don't reply to bot comments unless meaningful** — bots don't read replies
5. **Check for duplicate comments** — CodeQL often comments on same issue twice

## Quick Reference

```bash
# Fetch all review comments for a PR
curl -s "https://api.github.com/repos/{owner}/{repo}/pulls/{PR}/comments" \
  -H "Authorization: token $TOKEN" | jq '.[] | {path, line, user: .user.login, body: .body[0:200]}'

# Count comments by source
curl -s "https://api.github.com/repos/{owner}/{repo}/pulls/{PR}/comments" \
  -H "Authorization: token $TOKEN" | jq -r '.[].user.login' | sort | uniq -c

# Reply to a comment
curl -s -X POST "https://api.github.com/repos/{owner}/{repo}/pulls/{PR}/comments/{COMMENT_ID}/replies" \
  -H "Authorization: token $TOKEN" \
  -d '{"body": "Fixed in commit abc123"}'
```
