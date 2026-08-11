# Karpathy Coding Guidelines

Reference article on the Karpathy coding guidelines and how they are applied in
Hermes-CodeSpace. Wiki = reference knowledge; the executable procedure lives in
the skill `.devcontainer/skills/karpathy-coding-guidelines/SKILL.md`.

## Origin

Andrej Karpathy posted observations on LLM coding pitfalls
([tweet](https://x.com/karpathy/status/2015883857489522876)): models make wrong
assumptions and run with them, don't surface confusion or tradeoffs, overcomplicate
code with bloated abstractions, and change code they don't understand as side
effects. The [multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills)
repo (MIT, 200k+ stars) distilled those observations into a single behavioral
guideline file, shipped as CLAUDE.md, a Claude Code plugin, and a Cursor rule.

## The Four Principles

| Principle | Core idea | Failure mode it addresses |
|-----------|-----------|---------------------------|
| Think Before Coding | State assumptions, present interpretations, push back, stop when confused | Silent wrong assumptions, hidden confusion |
| Simplicity First | Minimum code that solves the problem; nothing speculative | Overcomplication, bloated abstractions |
| Surgical Changes | Touch only what the task requires; match existing style; clean only your own mess | Drive-by refactoring, orthogonal edits |
| Goal-Driven Execution | Convert imperative asks into verifiable goals with per-step verify checks | Unverifiable "make it work" loops |

## How It Maps to This Environment

- The procedure is encoded as a Hermes skill (procedural knowledge) at
  `.devcontainer/skills/karpathy-coding-guidelines/SKILL.md`, with before/after
  examples in its `references/examples.md`.
- The guidelines formalize preferences already established in this project:
  root-cause fixes over symptom patches, spare single-responsibility design, never
  weakening tests, verifiable completion criteria.
- The skill is auto-discovered via the skills symlink (`~/.hermes/skills/codespace`
  → `.devcontainer/skills`) and covered by the CI lint-check (markdownlint +
  SKILL.md validation). See [persistent-knowledge-proposal.md](persistent-knowledge-proposal.md)
  for the persistence architecture and [github-actions-testing-plan.md](github-actions-testing-plan.md)
  for the CI pipeline.

## Key Insight

The overcomplicated examples aren't obviously wrong — they follow design patterns
and best practices. The problem is timing: complexity added before it's needed is
harder to understand, more bug-prone, and harder to test. Good code solves
today's problem simply, not tomorrow's problem prematurely.
