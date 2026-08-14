# Wiki Index

> Reference knowledge base for Hermes-CodeSpace. Articles follow LM Wiki conventions — interlinked markdown articles forming a persistent knowledge base.

## Articles

| Article | Description | Tags |
|---------|-------------|------|
| [codespace-playbook.md](codespace-playbook.md) | Hermes Agent + GitHub Codespaces: auth, PR monitoring, git push, pitfalls | github, codespace, auth, tokens, pitfall |
| [repository-analysis.md](repository-analysis.md) | Repository deep dive — architecture, startup flow, verification, what's used vs unused | architecture, startup, verification, ci |
| [github-actions-testing-plan.md](github-actions-testing-plan.md) | CI/CD testing plan — phased approach, workflow design, service smoke tests, integration tests | ci, testing, github-actions, workflow |
| [persistent-knowledge-proposal.md](persistent-knowledge-proposal.md) | Architecture decision: persistent knowledge system via Git — symlinks, skills, wiki, Mnemon seeding | architecture, knowledge-persistence, symlink, devcontainer |
| [persistent-memory-proposal.md](persistent-memory-proposal.md) | Proposal for versioning Hermes MEMORY.md / USER.md via a symlink architecture (runtime vs tracked). | architecture, memory, persistence, symlink |
| [keepalive-proposal.md](keepalive-proposal.md) | Proposal: Codespace keepalive to mimic client activity and avoid idle shutdown (A: terminal heartbeat, B: /delay-shutdown pinger) | codespace, keepalive, idle-timeout, lifecycle, proposal |
| [codespace-lifecycle.md](codespace-lifecycle.md) | Reference: how Codespaces detects idle & shuts down, diagnosing container death, keeping a codespace alive | codespace, lifecycle, idle, keep-alive, shutdown, reference |
| [karpathy-coding-guidelines.md](karpathy-coding-guidelines.md) | Reference: Karpathy's LLM coding-pitfall guidelines — four principles, origin, how they map to Hermes skills | coding, discipline, guidelines, karpathy, reference |
| [lavish-axi-codespace-setup.md](lavish-axi-codespace-setup.md) | Complete setup & troubleshooting for lavish-axi in Codespaces: nginx proxy, port visibility, mermaid, feedback loop | lavish-axi, codespace, nginx, port-visibility, setup, mermaid |

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

*Last updated: 2026-08-02*