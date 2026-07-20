# GitHub Actions Testing Plan for Hermes-CodeSpace Dev Container

## Overview
This document outlines a phased approach to implementing GitHub Actions CI/CD for testing the dev container. The plan is designed for incremental adoption — start simple, add complexity as needed.

---

## Phase 1: Minimal Viable CI (Week 1)
**Goal**: Verify dev container builds and health check passes on every push/PR.

### Workflow File: `.github/workflows/devcontainer-ci.yml`

```yaml
name: Dev Container CI

on:
  push:
    branches: [main, readme]
  pull_request:
    branches: [main]

jobs:
  test-devcontainer:
    name: Build & Health Check
    runs-on: ubuntu-latest
    timeout-minutes: 25
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Build dev container & run health check
        uses: devcontainers/ci@v0.3
        with:
          imageName: hermes-codespace-test-${{ github.run_id }}
          push: never
          runCmd: |
            set -e
            echo "=== Running post-create (one-time setup) ==="
            bash .devcontainer/post-create-cmd.sh
            
            echo "=== Running post-start (service startup) ==="
            bash .devcontainer/post-start-cmd.sh &
            
            echo "=== Waiting for services to stabilize ==="
            sleep 60
            
            echo "=== Running health check ==="
            bash .devcontainer/self-check.sh
```

### Success Criteria
- [ ] Workflow runs on push to `main` and `readme`
- [ ] Workflow runs on PRs to `main`
- [ ] Build completes in < 20 minutes
- [ ] `self-check.sh` exits with code 0 (healthy)

---

## Phase 2: Service Smoke Tests (Week 2)
**Goal**: Verify each service responds on its expected port.

### Additional Steps in `runCmd`:

```bash
echo "=== Smoke testing service ports ==="
# ModelRelay
curl -sf http://localhost:7352/v1/models > /dev/null && echo "✓ ModelRelay (7352)" || echo "✗ ModelRelay"

# OmniRoute
curl -sf http://localhost:20128/v1/models > /dev/null && echo "✓ OmniRoute (20128)" || echo "✗ OmniRoute"

# Hermes Gateway
curl -sf http://localhost:9119/health > /dev/null && echo "✓ Hermes Gateway (9119)" || echo "✗ Hermes Gateway"

# Ollama
curl -sf http://localhost:11434/api/tags > /dev/null && echo "✓ Ollama (11434)" || echo "✗ Ollama"
```

### Success Criteria
- [ ] All 4 services respond to HTTP requests
- [ ] Failures are clearly reported in logs

---

## Phase 3: CLI & Integration Tests (Week 3)
**Goal**: Verify CLI tools work and can route requests.

### Additional Steps in `runCmd`:

```bash
echo "=== CLI version checks ==="
hermes --version
claude --version
omniroute --version
mnemon --version

echo "=== OmniRoute model listing ==="
omniroute model list

echo "=== Integration: Hermes one-shot via gateway ==="
# Start gateway in background if not already running
hermes gateway run &
sleep 10

# Test via REST API
curl -sf -X POST http://localhost:9119/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"auto-fastest","messages":[{"role":"user","content":"Say hello"}],"max_tokens":10}' \
  | jq -r '.choices[0].message.content' && echo "✓ Hermes API works" || echo "✗ Hermes API failed"
```

### Success Criteria
- [ ] All CLIs report versions without error
- [ ] OmniRoute lists configured models (including `auto-fastest`)
- [ ] Hermes gateway responds to chat completion request

---

## Phase 4: Memory & Persistence Tests (Week 4)
**Goal**: Verify Mnemon memory layer works across the stack.

### Additional Steps in `runCmd`:

```bash
echo "=== Mnemon memory test ==="
mnemon remember "CI test memory" --category test --importance 3
mnemon recall "CI test" --limit 1 | grep -q "CI test memory" && echo "✓ Mnemon works" || echo "✗ Mnemon failed"

echo "=== Hermes memory integration ==="
# Hermes should auto-use Mnemon when configured
hermes "Remember that the test value is 42" &
sleep 5
hermes "What is the test value?" | grep -q "42" && echo "✓ Hermes memory works" || echo "✗ Hermes memory failed"
```

---

## Phase 5: Optimizations & Enhancements (Ongoing)

| Enhancement | Effort | Benefit |
|-------------|--------|---------|
| **Docker layer caching** | Low | 50% faster builds |
| **Matrix testing** (Ubuntu latest + LTS) | Medium | Catch OS regressions |
| **Publish test images to GHCR** | Low | Debug failed builds locally |
| **Dependabot + auto-merge** | Low | Keep base image/deps current |
| **Parallel job for integration tests** | Medium | Faster feedback |
| **Annotate health check failures** | Low | Better PR UX |

### Docker Layer Caching Example:
```yaml
- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3

- name: Cache Docker layers
  uses: actions/cache@v4
  with:
    path: /tmp/.buildx-cache
    key: ${{ runner.os }}-buildx-${{ github.sha }}
    restore-keys: |
      ${{ runner.os }}-buildx-
```

---

## Implementation Checklist

### Files to Create/Modify
- [ ] `.github/workflows/devcontainer-ci.yml` (Phase 1)
- [ ] `.github/workflows/devcontainer-integration.yml` (Phase 3, optional separate workflow)
- [ ] Update `.devcontainer/self-check.sh` to output JSON for GitHub annotations (optional)

### Self-Check Script Enhancements (Optional)
Modify `self-check.sh` to support CI-friendly output:
```bash
# Add --json flag for machine-readable output
# Exit codes: 0=healthy, 1=warnings, 2=critical
# Output to /tmp/health-report.json (already done)
```

### GitHub Annotations (Optional)
```yaml
- name: Parse health report
  if: always()
  run: |
    if [ -f /tmp/health-report.json ]; then
      cat /tmp/health-report.json | jq -r '.checks[] | "::warning file=.devcontainer/self-check.sh::\(.name): \(.message)"'
    fi
```

---

## Estimated Timeline

| Phase | Est. Time | Cumulative |
|-------|-----------|------------|
| Phase 1: Minimal CI | 30 min | 30 min |
| Phase 2: Service Smoke | 20 min | 50 min |
| Phase 3: CLI Integration | 30 min | 80 min |
| Phase 4: Memory Tests | 20 min | 100 min |
| Phase 5: Optimizations | 60 min | 160 min |

---

## Next Agent Instructions

**To continue implementation:**

1. **Start with Phase 1** — Create `.github/workflows/devcontainer-ci.yml` using the minimal workflow above
2. **Test locally first** — Run `act` or push to a test branch to verify
3. **Iterate** — Add Phase 2-4 steps incrementally
4. **Monitor** — Watch first 5-10 runs for flakiness (free model APIs can be unreliable)

**Key files to reference:**
- `.devcontainer/post-create-cmd.sh` — One-time setup (~10 min)
- `.devcontainer/post-start-cmd.sh` — Service startup (~30 sec)
- `.devcontainer/self-check.sh` — Health check (exit codes: 0/1/2)
- `.devcontainer/Makefile` — Has `update-deps` target for upstream sync

**Common pitfalls to avoid:**
- Don't run `post-create-cmd.sh` on every CI run — it's slow. Consider a pre-built base image.
- Services need 45-60s to fully start; `sleep 60` is conservative but reliable.
- Free model endpoints (OmniRoute/ModelRelay) may return 5xx — health check should distinguish infra vs. model failures.

---

## Decision Points for User

Before Phase 2+, confirm:
1. **Should CI run on every push, or only PRs + main?**
2. **Acceptable CI runtime?** (Current: ~15-20 min with full post-create)
3. **Publish test images to GHCR** for debugging failed builds?
4. **Separate integration workflow?** (Runs less frequently, more thorough)
5. **Annotate PRs with health check failures?** (Requires self-check JSON output)

---

*Generated: 2026-07-19*
*Branch: readme*
*Next: Implement Phase 1 workflow*