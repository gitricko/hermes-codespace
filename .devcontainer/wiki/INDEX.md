# Wiki Index

> Reference knowledge base for Hermes-CodeSpace. Articles follow LM Wiki conventions — interlinked markdown articles forming a persistent knowledge base.

## Articles

| Article | Description | Tags |
|---------|-------------|------|
| [codespace-playbook.md](codespace-playbook.md) | Hermes Agent + GitHub Codespaces: auth, PR monitoring, git push, pitfalls | github, codespace, auth, tokens, pitfall |
| [repository-analysis.md](repository-analysis.md) | Repository deep dive — architecture, startup flow, verification, what's used vs unused | architecture, startup, verification, ci |
| [github-actions-testing-plan.md](github-actions-testing-plan.md) | CI/CD testing plan — phased approach, workflow design, service smoke tests, integration tests | ci, testing, github-actions, workflow |
| [persistent-knowledge-proposal.md](persistent-knowledge-proposal.md) | Architecture decision: persistent knowledge system via Git — symlinks, skills, wiki, Mnemon seeding | architecture, knowledge-persistence, symlink, devcontainer |
| [persistent-memory-proposal.md](persistent-memory-proposal.md) | Proposal for versioning Hermes MEMORY.md / USER.md via a symlink architecture (runtime vs tracked) | architecture, memory, persistence, symlink |
| [keepalive-proposal.md](keepalive-proposal.md) | Proposal: Codespace keepalive to mimic client activity and avoid idle shutdown (A: terminal heartbeat, B: /delay-shutdown pinger) | codespace, keepalive, idle-timeout, lifecycle, proposal |
| [codespace-lifecycle.md](codespace-lifecycle.md) | Reference: how Codespaces detects idle & shuts down, diagnosing container death, keeping a codespace alive | codespace, lifecycle, idle, keep-alive, shutdown, reference |
| [mnemon-graph-viewer.md](mnemon-graph-viewer.md) | Reference: 3D Mnemon knowledge-graph viewer — pipeline, data model, key design decisions, regeneration | mnemon, knowledge-graph, visualization, 3d-force-graph, tool |
| [karpathy-coding-guidelines.md](karpathy-coding-guidelines.md) | Reference: Karpathy's LLM coding-pitfall guidelines — four principles, origin, how they map to Hermes skills | coding, discipline, guidelines, karpathy, reference |
| [codespace-gh-auth.md](codespace-gh-auth.md) | Extract real GitHub OAuth token from VS Code server process for API and gh CLI in Codespaces | codespace, github, auth, token, vscode, skill |
| [codespace-persistent-symlinks.md](codespace-persistent-symlinks.md) | Whole-folder symlink pattern to persist Hermes memories and skills across Codespace rebuilds | codespace, persistence, symlink, memory, skill |
| [codespace-port-visibility.md](codespace-port-visibility.md) | Automate Codespace port visibility via CLI: forward + public/private visibility using gh CLI | codespace, ports, visibility, github, automation, skill |
| [codespace-lavish.md](codespace-lavish.md) | Headed Lavish-AXI whiteboard over noVNC in Codespaces — architecture, session key, feedback loop, prerequisites | codespace, lavish, whiteboard, novnc, gui, skill |
| [github-codespace.md](github-codespace.md) | Full GitHub Codespace workflow: auth, CI monitoring, debugging, API access, PR operations | github, codespace, ci, debugging, api, workflow, skill |
| [github-pr-review.md](github-pr-review.md) | Evaluate CodeQL and Copilot suggestions on PRs — fetch, triage, propose fixes with decision framework | github, pr, codeql, copilot, review, security, skill |
| [memory-automation.md](memory-automation.md) | Automated Mnemon workflow: recall on start, recall before turn, auto-save after response | memory, mnemon, persistence, automation, workflow, skill |
| [mnemon-seed-persistence.md](mnemon-seed-persistence.md) | Persist Mnemon memory across Codespace rebuilds via checked-in seed.json with validation | mnemon, seed, persistence, codespace, memory, skill |
| [persistent-knowledge.md](persistent-knowledge.md) | Persistent skills/knowledge in Codespace via symlinks — validated pattern and self-check wiring | persistence, symlink, codespace, knowledge, skill |
| [vscode-cli-codespaces.md](vscode-cli-codespaces.md) | Auto-discover VS Code CLI in Codespaces and open files in connected editor | codespace, vscode, editor, cli, skill |
| [ci-lint-check.md](ci-lint-check.md) | Pre-commit CI lint validation — run locally before push to avoid GitHub Actions failures | ci, lint, pre-commit, validation, github-actions, skill |
| [codespace-webtop.md](codespace-webtop.md) | Native Selkies/XFCE webtop (browser desktop) via pixelflux-based selkies — architecture, WebSocket-only streaming, XFCE failsafe fix, port 3000 | selkies, xfce, webtop, desktop, websocket, codespace, browser-desktop, skill |
| [selkies-package-discrepancy.md](selkies-package-discrepancy.md) | Critical: PyPI `selkies==1.6.1` is legacy GStreamer; correct pixelflux-based package is a GitHub Actions artifact | selkies, package, pixelflux, webrtc, gotcha |

## How to Use

- **Read an article**: `read_file(path=".devcontainer/wiki/<article>.md")`
- **Create a new article**: Write to `.devcontainer/wiki/<topic>.md`, then update this INDEX.md
- **Link between articles**: Use relative markdown links `[text](other-article.md)`

## Guidelines

- Skill = procedural knowledge ("how to do X") → `.devcontainer/skills/`
- Wiki article = reference knowledge ("how system Y works") → `.devcontainer/wiki/`
- Insight/fact = single line → Mnemon (not committed to git)

## Adding New Articles

1. Create `<topic>.md` in this directory
2. Add a row to the table above
3. File is uncommitted — user reviews via `git diff` and decides to commit

---

*Last updated: 2026-08-19*