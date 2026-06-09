# PRD quality rubric

> Used by `graders/llm_grader.py` to grade pm-agent's PRD output.
> Score each dimension 0–10. Passing threshold (set per-eval): default 7 average.

## Dimensions

### 1. Scope clarity (0–10)

- **10**: Exactly what's in and out. A reader could draw a box around the work without ambiguity.
- **7**: In-scope is clear; out-of-scope implied but not enumerated.
- **4**: Scope inferable only by reading the whole doc.
- **0**: Scope unclear or contradictory.

### 2. Acceptance criteria (0–10)

- **10**: Each AC is a single observable behavior the QA agent could verify. No "well" or "should ideally" language. Edge cases enumerated.
- **7**: Most AC are observable; a few subjective.
- **4**: AC are aspirational ("users should love it").
- **0**: No AC, or AC restate the scope.

### 3. Open questions surfaced (0–10)

- **10**: Genuine unknowns called out with proposed resolution path (who decides, by when, what blocks).
- **7**: Open questions listed but no resolution path.
- **4**: One or two perfunctory "TBDs".
- **0**: No open questions despite obvious ambiguity.

### 4. Slice-ability into PRs (0–10)

- **10**: PRD includes a proposed PR breakdown. Each slice is independently shippable + reviewable. No slice exceeds ~500 LOC.
- **7**: PR breakdown present but some slices look oversized.
- **4**: PR breakdown is just "implement everything".
- **0**: No PR breakdown.

## Scoring

```
final_score = (scope + acceptance + open_questions + sliceability) / 4
pass = final_score >= passing_threshold
```

## Calibration

Three reference PRDs lived in `evals/rubrics/calibration/prd-quality/` once we have human-rated examples (P=10, P=7, P=4). The LLM grader receives all three as few-shot context before scoring the candidate. This is how we keep the grader from drifting.

*(Calibration set is empty at template-init; populate after the first 5 real PRDs are graded by a human.)*
