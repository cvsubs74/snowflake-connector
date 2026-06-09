# docs/contracts/ — Generator ↔ Evaluator sprint contracts

From the [harness-design post](https://www.anthropic.com/engineering/harness-design-long-running-apps): reliable multi-hour builds come from **negotiating testable acceptance criteria before coding starts**, then writing them to a file the Generator and Evaluator both treat as authoritative.

In our 8-agent topology:

- **Planner** = pm-agent + designer-agent (produces the PRD and DESIGN doc)
- **Generator** = dev-agent (writes the code)
- **Evaluator** = qa-agent + code-reviewer-agent (verifies)

The contract bridges them. It is **the single artifact that determines whether the work is done.**

## When to write a contract

- Any enhancement that's `prioritized,priority:high` or `medium`.
- Any bug that requires more than a one-line fix.
- Any architectural change touching more than one module.

Skip the contract for: trivial bugs (one-line fixes, typo corrections), docs-only changes, refactors that touch no observable behavior.

## How to write one

1. **Dev opens a draft contract** at `docs/contracts/<issue-number>-<slug>.md` from the template below, on the working branch, before touching implementation code.
2. **Dev fills the "Generator commits to" section.** What will be true when implementation is done — observable, file-pathed, testable.
3. **QA + Code Reviewer fill the "Evaluator commits to" section.** Each acceptance criterion gets a verification method. If a criterion is too vague to verify, kick it back.
4. **Both sign by name in the Sign-off block** before code is written.
5. **Contract lives in the PR.** Anyone reviewing can see what "done" means.

## Lifecycle

- Once signed, the contract is **append-only** during implementation. Changes require both signatures again.
- When the PR merges, the contract stays in the repo. It's the audit trail for "what was promised vs. what shipped."
- Renegotiate (= new signatures) if scope changes during build. Do not silently drift.

## The template

See `_template.md` in this directory. Copy, fill, commit on the working branch alongside your first code commit.

## Related skills

- `contract-negotiation` — walks through writing one
- `eval-runner` — every contract criterion should map to (or generate) an eval task once stable
