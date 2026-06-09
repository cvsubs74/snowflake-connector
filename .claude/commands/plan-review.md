---
description: Run CEO / engineering / design review lenses on a plan or design doc.
---

# Plan Review

Adapted from [garrytan/gstack](https://github.com/garrytan/gstack)'s `/plan-ceo-review`, `/plan-eng-review`, and `/plan-design-review` — used and credited under MIT license.

Run three review lenses on a plan or design doc the operator points you to (or the most recent doc in `docs/prd/` or `docs/design/` if not specified). The lenses are independent — apply each fully before moving to the next.

## Inputs

- `$1` (optional) — path to the plan / PRD / design doc. If omitted, ask the operator which doc to review.

## Lens 1 — CEO review (Strategic)

Read the doc with these questions in mind:

1. **What's the 10-star product hiding inside this request?** Is the team aiming for the minimum viable thing when something more ambitious is within reach for similar effort?
2. **Is this the right problem?** Could a different (smaller / larger / orthogonal) problem solve more of the underlying pain?
3. **Scope mode** — pick one:
   - **EXPANSION** — the team is under-scoping; recommend boiling more of the lake.
   - **SELECTIVE EXPANSION** — add one specific capability that turns this from "shipped feature" into "shipped product."
   - **HOLD SCOPE** — the team is right; ship as planned.
   - **REDUCTION** — the team is over-scoping; recommend a narrower wedge that validates the bet first.
4. **What's the bet?** If we're wrong about a key assumption, what do we waste?

Output the CEO review as a section labeled `## CEO Review` with the scope mode + 2–4 bullets explaining your call.

## Lens 2 — Engineering review (Architecture)

Read the doc with these questions in mind:

1. **Hidden assumptions** — what's the doc treating as given that should be made explicit (tests, asserts, runtime checks)?
2. **Data flow** — sketch the data flow in ASCII. Where does data enter, transform, persist, leave? Are there cycles or back-pressure points?
3. **State machine** — for any non-trivial state (auth, multi-step wizard, async work), draw the state diagram. Are there unreachable states? Trapping states?
4. **Failure modes** — what happens when each external dependency is down / slow / returns wrong data? Are those failures handled or do they cascade?
5. **Test matrix** — does the plan cover unit, integration, and E2E? Are the most likely failure modes specifically tested?
6. **Cross-flow contracts** — if this touches shared schemas / APIs / IPC, does the plan update both sides?
7. **Performance / scale** — what breaks first when load 10x's? Is that acceptable for the timeline?
8. **Security** — auth boundaries, input validation, secrets handling. Anything STRIDE-worthy?

Output the engineering review as a section labeled `## Engineering Review` with concrete change requests against the plan (not just generic advice).

## Lens 3 — Design review (UX, only if user-facing)

Skip if the plan is backend-only or developer-facing. Otherwise read with:

1. **Mockup all key screens.** ASCII is fine. Don't approve a plan you haven't visualized.
2. **State coverage** — empty state, loading state, error state, success state, edge cases (very long content, very short, missing data, slow network). Are they all designed?
3. **Accessibility** — keyboard nav, screen reader semantics, color contrast, focus management.
4. **Responsive** — mobile, tablet, desktop. Touch targets ≥44px on mobile.
5. **Design-system adherence** — using existing tokens / components, or rolling new ones?
6. **AI slop scan** — generic Tailwind defaults, lorem ipsum, placeholder gradients, unmotivated drop shadows. Specific over generic.

Output the design review as a section labeled `## Design Review` with concrete change requests + a 0–10 rating per dimension (UX clarity, accessibility, polish, design-system fit). Note what a 10 would look like for any dimension scoring <8.

## Final output shape

```markdown
# Plan Review: <doc title>

## Summary
<one-line verdict — Approve as-is / Approve with changes / Recommend rework>

## CEO Review
<scope mode + bullets>

## Engineering Review
<concrete change requests>

## Design Review (if applicable)
<concrete change requests + ratings>

## Recommended next step
<one of: ship as-is / Dev incorporates changes inline / PM re-scopes / operator decides between alternatives>
```

Always end with one clear next step. A review without a next step is just opinion.
