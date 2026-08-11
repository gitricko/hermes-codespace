# Examples: Karpathy Guidelines in Practice

Concrete before/after pairs demonstrating the four principles. Adapted from
[multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills)
EXAMPLES.md (MIT). Load this file when a principle needs illustration during a
code task, review, or when explaining a correction to the user.

## 1. Think Before Coding

### Hidden Assumptions

User request: "Add a feature to export user data"

**Wrong (silent assumptions):** assumed export ALL users, assumed file location,
assumed fields, assumed CSV format — no questions asked.

**Right (surface assumptions before implementing):**

```
Before implementing, I need to clarify:

1. Scope: Export all users or filtered subset? (privacy implications)
2. Format: Did you mean:
   - Download file in browser?
   - Background job with email notification?
   - API endpoint returning data?
3. Fields: Which user fields? (some might be sensitive)
4. Volume: How many users typically? (affects approach)

Simplest approach: API endpoint returning paginated JSON.
What's your preference?
```

## 2. Simplicity First

### Over-abstraction

User request: "Add a function to calculate discount"

**Wrong:** Strategy pattern with ABC, Protocol, dataclasses, DiscountConfig,
30+ lines of setup — for a single percentage calculation.

**Right:**

```python
def calculate_discount(amount: float, percent: float) -> float:
    """Calculate discount amount. percent should be 0-100."""
    return amount * (percent / 100)

discount = calculate_discount(100.0, 10.0)  # $10 off
```

Add complexity only when you actually need multiple discount types. If that
requirement comes later, refactor then.

### Speculative Features

User request: "Save user preferences to database"

**Wrong:** PreferenceManager class with cache, validator, merge, notify options —
features nobody asked for.

**Right:**

```python
def save_preferences(db, user_id: int, preferences: dict):
    """Save user preferences to database."""
    db.execute(
        "UPDATE users SET preferences = ? WHERE id = ?",
        (json.dumps(preferences), user_id)
    )
```

Add later if needed: caching (when performance matters), validation (when bad
data appears), merging (when the requirement emerges).

## 3. Surgical Changes

### Drive-by Refactoring

User request: "Fix the bug where empty emails crash the validator"

**Wrong:** "Improved" email validation beyond the bug, added username validation
nobody asked for, changed comments, added a docstring.

**Right:** only the lines that fix empty-email handling:

```diff
  def validate_user(user_data):
      # Check email format
-     if not user_data.get('email'):
+     email = user_data.get('email', '')
+     if not email or not email.strip():
          raise ValueError("Email required")
```

### Style Drift

User request: "Add logging to the upload function"

**Wrong:** changed quote style, added type hints and docstring, reformatted
whitespace, changed boolean return logic.

**Right:** only added logging lines; matched existing style (single quotes, no
type hints, existing return pattern).

## 4. Goal-Driven Execution

### Vague vs. Verifiable

User request: "Fix the authentication system"

**Wrong:** "I'll review the code, identify issues, make improvements, test" —
no success criteria.

**Right:** ask what specific issue, then plan with verify per step:

```
If the issue is "users stay logged in after password change":

1. Write test: change password → verify old session invalidated
   Verify: test fails (reproduces bug)
2. Implement: invalidate sessions on password change
   Verify: test passes
3. Edge cases: multiple active sessions, concurrent changes
   Verify: additional tests pass
4. No regression: existing auth tests still pass
   Verify: full test suite green
```

### Test-First Verification

User request: "The sorting breaks when there are duplicate scores"

**Wrong:** immediately changed sort logic without confirming the bug.

**Right:** write a reproducing test first (run 10x, see inconsistent ordering),
then fix with a stable sort key `(-score, name)`, then verify the test passes
consistently.

## Anti-Patterns Summary

| Principle | Anti-Pattern | Fix |
|-----------|--------------|-----|
| Think Before Coding | Silently assumes format, fields, scope | List assumptions, ask |
| Simplicity First | Strategy pattern for one calculation | One function until needed |
| Surgical Changes | Reformats quotes, adds type hints mid-fix | Only change lines fixing the issue |
| Goal-Driven | "I'll review and improve the code" | "Test for bug X → make pass → verify no regressions" |

## Key Insight

The "overcomplicated" examples aren't obviously wrong — they follow design
patterns and best practices. The problem is timing: complexity added before it's
needed makes code harder to understand, introduces more bugs, takes longer, and
is harder to test. Good code solves today's problem simply, not tomorrow's
problem prematurely.
