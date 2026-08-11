---
name: karpathy-coding-guidelines
description: "Karpathy's coding discipline: minimal, surgical, verified."
version: 1.0.0
author: multica-ai (jiayuan_jy), Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [coding, discipline, simplicity, code-review, refactoring]
    related_skills: [systematic-debugging, test-driven-development, simplify-code, requesting-code-review]
---

# Karpathy Coding Guidelines

Behavioral discipline for writing, reviewing, and refactoring code, derived from
Andrej Karpathy's observations on LLM coding pitfalls and the
[multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills)
repo (MIT). Four principles: think before coding, keep it simple, make surgical
changes, execute toward verifiable goals.

This is a behavior skill, not a tool skill: it changes how code tasks are planned
and executed. It applies to any language and complements tool-specific workflows.

## When to Use

Use when the user asks you to:

- Write, edit, or extend code in any language
- Review a diff, PR, or code change
- Refactor or simplify existing code
- Fix a bug (reproduce first)
- Plan a multi-step implementation or commit series

Don't use for:

- Trivial one-liners, typo fixes, simple renames — the tradeoff note applies
- Throwaway experiments where speed matters more than durability

## Prerequisites

None. This is behavioral discipline; it applies to every code task regardless of
tooling. No env vars, no installs.

## The Discipline

Work through the four principles in order. Each ends with a checkable criterion.

### 1. Think Before Coding

Don't assume. Don't hide confusion. Surface tradeoffs.

- State assumptions explicitly before implementing. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

Criterion: no assumption survives silently into the implementation. Every
assumption is either stated in the plan or resolved by a question before code is
written.

### 2. Simplicity First

Minimum code that solves the problem. Nothing speculative.

- No features beyond what was asked
- No abstractions for single-use code
- No "flexibility" or "configurability" that wasn't requested
- No error handling for impossible scenarios
- If you write 200 lines and it could be 50, rewrite it

Test: would a senior engineer call this overcomplicated? If yes, simplify.

Criterion: every element of the solution traces to a stated requirement; nothing
exists "just in case."

### 3. Surgical Changes

Touch only what you must. Clean up only your own mess.

When editing existing code:

- Don't "improve" adjacent code, comments, or formatting
- Don't refactor things that aren't broken
- Match existing style, even if you'd do it differently
- If you notice unrelated dead code, mention it — don't delete it

When your changes create orphans:

- Remove imports/variables/functions that YOUR changes made unused
- Don't remove pre-existing dead code unless asked

Criterion: every changed line in the diff traces directly to the user's request
(review the diff before finishing).

### 4. Goal-Driven Execution

Define success criteria. Loop until verified.

Transform imperative tasks into verifiable goals:

- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan with a verify check per step:

1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]

Strong success criteria let you loop independently. Weak criteria ("make it
work") require constant clarification.

Criterion: each step has a checkable verification, and the final state is proven
by actual test/command output — not by assertion.

## Pitfalls

- **Caution over speed.** These rules bias toward rigor. For trivial tasks (typo
  fixes, obvious one-liners), use judgment — not every change needs the full loop.
- **Don't stall on questions.** Ask once, with options and a recommendation. If
  the user doesn't answer, proceed on the stated default. Asking is not a
  substitute for finishing.
- **Simplicity isn't stripping needed functionality.** The minimal version must
  still solve the real problem, including edge cases the user explicitly cares
  about.
- **Verification must be real.** The verify step is satisfied by actual tool
  output (tests run, commands executed). Never claim verified without running it.
- **Don't over-apply to throwaway work.** Sandbox experiments and spikes don't
  need the full discipline — apply it where the result will be committed or
  reviewed.

## Verification

The skill worked if, at the end of a code task:

- [ ] Clarifying questions (if any) came before implementation, not after mistakes
- [ ] Diff contains only requested changes — no drive-by refactoring or style drift
- [ ] Code is minimal: no speculative abstractions, config, or error handling
- [ ] Success criteria defined up front; final state verified by real output
      (tests/commands run)

Concrete before/after examples for each principle:
`references/examples.md`.
