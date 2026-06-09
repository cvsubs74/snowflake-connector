---
description: Systematic root-cause debugging. Iron Law — no fixes without investigation.
---

# Investigate

Adapted from [garrytan/gstack](https://github.com/garrytan/gstack)'s `/investigate` — used and credited under MIT license.

## Iron Law

**No fixes without an investigation.** This skill produces a root-cause hypothesis backed by evidence. Implementing the fix happens AFTER the investigation, in a separate step. If you find yourself proposing a fix in the first 30 seconds, you're guessing — restart with this skill.

## Inputs

- `$1` (required) — the symptom or failing test. Examples: "PR #N's CI is red", "user reports button does nothing on mobile", "schema validator rejects payload X".

## Process

### 1. Reproduce

Before any hypothesis, reproduce the symptom.

- If it's a failing test: run it locally. Capture the actual output.
- If it's a user-reported bug: follow the repro steps. Capture screenshots / logs.
- If it's intermittent: don't skip reproduction — run multiple times and note the failure rate. Intermittent failures are still reproducible, just stochastically.

**If you can't reproduce:** STOP. State what you tried, what you expected, what you got. Don't proceed to hypothesis until you can reproduce the symptom on demand. Ask the operator for additional repro detail.

### 2. Trace

Trace the data / control flow from the symptom backwards toward the cause:

- For a failing test: read the assertion, then the code path that should produce the asserted value, then the code path that actually produces it.
- For a user-visible bug: trace from the UI event → frontend handler → API call → backend handler → data store. Pause at each boundary; verify the data shape at that boundary.
- For a performance regression: trace from the slow operation backward through the call graph; look for the largest leaf.

Capture observations as a numbered list, evidence cited:

```
1. UI button onClick fires the right handler (verified: added console.log)
2. Handler calls POST /api/X with payload Y (verified: network tab)
3. Backend logs show /api/X received payload Y' (NOT Y) — payload diverged
4. ... (continue)
```

### 3. Hypothesize (one at a time)

Form ONE falsifiable hypothesis at a time. Examples:

- "The frontend's payload-encoder drops field Z when the user has not interacted with input Z."
- "The validator at validator.py:142 was strengthened in PR #N and now rejects payloads it previously accepted."
- "Service Y's deploy on $DATE introduced a regression in path Z."

Each hypothesis must be:

- **Falsifiable** — there's a specific test that would prove it wrong.
- **Specific** — names files, functions, commits.
- **Singular** — one cause, not "maybe X or Y or Z."

### 4. Test the hypothesis

Design the experiment that would refute the hypothesis. Run it. Observe.

- If refuted: cross it off. Form the next hypothesis.
- If supported: that's your candidate root cause. Continue to step 5.

### 5. Confirm

A "supported" hypothesis is not a confirmed root cause. Validate:

- Can you produce the symptom AT WILL by triggering the suspected cause?
- Can you make the symptom DISAPPEAR by reverting the suspected cause (without changing anything else)?

Both must be true for confirmed root cause.

### 6. Stop-after-3 rule

If you've proposed 3 fixes and none worked: STOP. You're chasing symptoms, not the cause. Restart from step 1 — your reproduction or trace was insufficient.

## Output

Post the investigation as a comment on the bug issue (or in chat if there's no issue yet):

```markdown
## Investigation: <symptom>

### Reproduction
<how to reproduce, with frequency if intermittent>

### Trace
1. <observation> (evidence: <how verified>)
2. <observation> (evidence: ...)
3. ...

### Hypothesis
<one specific, falsifiable hypothesis>

### Confirmation
- Produced at will by: <action>
- Disappeared by reverting: <change>

### Root cause
<one sentence — what's actually wrong>

### Suggested fix
<one sentence — what to change. NOT the fix itself; that's the implementer's job.>

### Files implicated
- <file:line> — <what's wrong here>
```

The fix is implemented as a separate step (Dev Agent picks up from this investigation, or operator approves the fix scope before code is written).

## Anti-patterns

- **Skipping reproduction** to save time. The fix you ship without reproducing the bug is usually a fix for the wrong bug.
- **Bundling investigation and fix.** Mixing the two leads to "I think this is it" fixes that turn out to be wrong.
- **Multiple simultaneous hypotheses.** Pick one. Test it. Move on. Multi-tracking hypotheses leads to confused investigations and confused fixes.
- **"I'll just try this and see."** That's not investigation; that's gambling.
