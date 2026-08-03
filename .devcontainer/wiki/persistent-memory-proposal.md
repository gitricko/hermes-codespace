# Proposal: Persistent Memory System for Hermes

## Overview
This document proposes a versioning system for Hermes's MEMORY.md and USER.md files to make them persistent across Codespace sessions, addressing the core challenge of maintaining behavioral rules and user preferences between rebuilds.

## Current State
MEMORY.md and USER.md exist in `~/.hermes/memories/`
These files are injected into the system prompt every turn (behavioral enforcement)
However, they're not versioned and get lost on Codespace rebuild
There's no built-in mechanism to persist these files across sessions

## The Solution: Symlink Architecture
Propose a **symlink architecture** that preserves the behavioral enforcement while making memories durable and reviewable.

### Core Design
The **whole runtime memories folder** is symlinked to the tracked dir — the exact
skills pattern (`~/.hermes/skills/<project> -> .devcontainer/skills`):
```
Runtime:  ~/.hermes/memories            ← behavioral rules + user profile, injected every turn
           (a symlink pointing at the tracked dir)

Tracked:  .devcontainer/memories/        ← git-tracked, survives rebuilds
              MEMORY.md   (behavioral reminders)
              USER.md     (user preferences / profile)
              .gitignore  (excludes ephemeral *.lock / *.log)

Boot scripts:
  post-create-cmd.sh  → authoritative creation (runs once on a FRESH container, right
                        after Hermes is installed, before it instantiates ~/.hermes/memories)
  start-hermes.sh     → slim repair guard (creates the link if a pre-existing container
                        never got it)
```
Because runtime and tracked are the same directory, edits to MEMORY.md/USER.md are
immediately reflected in both — no copy-back-and-forth between `.hermes` and the repo.

### Why Symlink Beats Mirror
- **No copy complexity**: Single file serves both purposes
- **Immediate visibility**: Changes in tracked version appear instantly in runtime
- **Git review**: All memory changes go through standard git workflow
- **Consistent with skills**: Uses the exact same pattern as `.devcontainer/skills/`

### Skills Pattern (Reference)
Skills use a **symlink approach**:
```
Runtime:  ~/.hermes/skills/<project>/SKILL.md
Tracked:  .devcontainer/skills/<project>/SKILL.md
Symlink:  ~/.hermes/skills/<project> -> .devcontainer/skills/<project>
```

### Our Proposal for Memories (Folder Symlink)
We link the **whole runtime memories folder** — the exact skills pattern (`~/.hermes/skills/<project> -> .devcontainer/skills`):
```
Runtime:  ~/.hermes/memories  (points to the tracked dir)
Tracked:  .devcontainer/memories/
Symlink:  ~/.hermes/memories -> .devcontainer/memories
```
Ephemeral `.lock`/`.log` files Hermes writes inside the dir are excluded via
`.devcontainer/memories/.gitignore`, so the repo tracks only MEMORY.md and USER.md.

## Behavioral Enforcement Strategy

### Key Insight
The **behavioral rule** (e.g., "load codespace skills before GitHub ops") MUST live in **MEMORY.md**, NOT Mnemon, because:

1. **Injection timing:** MEMORY.md is injected *every turn* unconditionally
2. **Recall limitation:** Mnemon is recall-based - I must remember to query it
3. **Enforcement guarantee:** Only MEMORY.md provides automatic behavioral steering

### Implementation
```bash
# Behavioral rule example
# In runtime: ~/.hermes/memories/MEMORY.md
# Before any GitHub operation, load the following Hermes skills:
# - github-codespace
# - codespace-gh-auth
# This ensures consistent GitHub workflow regardless of session context.
```

### Why Both Memory.md AND Mnemon?
- **MEMORY.md:** Behavioral enforcement (injected every turn)
- **Mnemon + seed.json:** Durable knowledge base (queries on demand)
- **Wiki/Skills:** Procedural documentation (read-only reference)

## Trade-offs and Design Decisions

### Write Frequency vs. Review Burden
**Problem:** MEMORY.md is written frequently (every behavioral decision)
**Solution:** Make only *important* updates worthy of review

**Approach:**
- Frequent runtime edits (immediate effect via symlink)
- Manual commits for important changes (behavioral rule updates)

### Privacy and Data Control
**Problem:** USER.md may contain sensitive user preferences
**Solution:**
- Runtime stays private and ephemeral
- Tracked copy provides controlled persistence
- User can review and sanitize before committing

### Performance and Scalability
**Problem:** Symlinking on every start could be redundant
**Solution:**
- Symlinks are lightweight (filesystem operations)
- Only one folder symlink is created (minimal overhead)
- Implemented in post-create-cmd.sh (runs once) + a guard in start-hermes.sh

## Implementation Plan

### Phase 1: Core Symlink Infrastructure
1. **Create tracked directory:** `.devcontainer/memories/`
2. **post-create-cmd.sh:** Add authoritative symlink creation (right after Hermes install, once per fresh container)
3. **start-hermes.sh:** Add the slim repair guard (only for pre-existing containers)
4. **Confirm MEMORY.md/USER.md committed:** so the symlink always resolves on first boot

### Phase 2: Behavioral Rule Migration
1. **Move behavioral rules:** From runtime to tracked symlink
2. **Update MEMORY.md content:** Add behavioral enforcement rules
3. **Seed seed.json:** Copy important behavioral rules for Mnemon
4. **Update wiki:** Document behavioral rule conventions

### Phase 3: Integration and Validation
1. **Test symlinks:** Verify creation and update mechanisms
2. **Validate injection:** Confirm MEMORY.md still injects correctly
3. **Review process:** Test git diff/review workflow
4. **Documentation update:** Wiki and mnemon entries

## Files to Modify

### Core Changes
- `post-create-cmd.sh`: Authoritative symlink creation for memories (once per fresh container)
- `start-hermes.sh`: Slim repair guard (pre-existing containers only)
- `~/.hermes/memories/MEMORY.md`: Behavioral rules (runtime, via symlink)
- `~/.hermes/memories/USER.md`: User preferences (runtime, via symlink)

### Repository Files (to be committed)
- `.devcontainer/memories/MEMORY.md`: Tracked reminders
- `.devcontainer/memories/USER.md`: Tracked profile
- `.devcontainer/memories/.gitignore`: Prevent .lock files from being tracked
- `.devcontainer/wiki/persistent-memory-proposal.md`: Updated documentation

### Mnemon Integration
- `.devcontainer/mnemon/seed.json`: Behavioral rule summaries
- `.devcontainer/mnemon/validate-seed.py`: Validation script updates

## Review and Approval Process

### Initial Commit (Phase 2)
```bash
# User reviews behavioral rules
# Decides which rules need persistence
# Commits tracked copy
# Merges PR
```

### Continuous Maintenance
```bash
# User edits behavioral rules in runtime (through symlink)
# Symlink maintains both runtime and tracked version
# User reviews via git diff before committing
# Changes persist across Codespace rebuilds
```

## Success Criteria

### Functional
1. **Behavioral enforcement:** Hermes follows behavioral rules from MEMORY.md
2. **Persistence:** Rules survive Codespace rebuilds via symlink
3. **Review process:** All important changes go through git review
4. **No regression:** Existing functionality remains unchanged
5. **Automated safety net:** `self-check.sh` `Persistence` section asserts both the
   memories and skills symlinks (plus tracked content); CI `full-build` runs it and
   fails if either symlink drifts.

### Operational
1. **Recovery:** Runtime can be restored from tracked version
2. **Performance:** Symlink overhead is negligible
3. **Privacy:** Sensitive user data is properly handled
4. **Documentation:** All changes are well-documented

## Benefits

### For Users
1. **Consistent experience:** Behavioral rules persist across sessions
2. **Reduced friction:** No need to re-establish conventions
3. **Better governance:** Rules go through review process
4. **Recovery safety:** Lost sessions can be restored

### For the System
1. **Automation:** Behavioral enforcement works without user intervention
2. **Scalability:** Rules are versioned and reviewable
3. **Maintainability:** Clear separation of concerns
4. **Reliability:** Mirrors the proven skills pattern

## Open Questions

1. **Content policy:** What should/shouldn't be in USER.md vs. MEMORY.md?
2. **Review cadence:** How frequently should users commit memory changes?
3. **Conflict resolution:** How to handle concurrent edits across codespaces?
4. **Privacy boundaries:** What user preferences should never be tracked?

## Next Steps

1. **Draft implementation:** Add symlink logic to post-create-cmd.sh + guard to start-hermes.sh
2. **Test symlinks:** Verify creation and update mechanisms
3. **Populate tracked version:** Move existing behavioral rules
4. **Document process:** Update wiki and add mnemon entries
5. **Review and commit:** User reviews and approves changes
6. **Deploy:** Full integration and validation

## Conclusion

The symlink architecture provides a practical solution to the persistence challenge while maintaining the behavioral enforcement capabilities that make Hermes effective. By following the exact same pattern as skills, we achieve:

1. **Immediate behavioral enforcement** through runtime MEMORY.md injection
2. **Durable, reviewable persistence** through tracked symlinks
3. **Clean separation** between runtime state and versioned knowledge
4. **Integration** with existing Mnemon and wiki systems

This approach balances the need for persistent behavioral rules with the practical considerations of frequent edits and privacy concerns.

---

*Last updated: 2026-08-02*
*Status: Proposal - Ready for review and implementation*
*Author: Hermes Agent Development Team*