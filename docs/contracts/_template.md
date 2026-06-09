# Contract: <one-line description of the work>

> Issue: #<N> · Branch: `<type>/<N>-<slug>` · PRD: `docs/prd/PRD-<topic>.md` (if applicable)
>
> Created: <YYYY-MM-DD> · Signed: <YYYY-MM-DD>

---

## Context

<One paragraph: what's the user-visible change, why does it matter, what's the scope boundary.>

## Generator commits to

> **dev-agent fills this.** What will be true when implementation is done. Each item must be observable (a file at a path, a test passing, a CLI exit code, a UI state).

- [ ] **Code change**: <files touched, with paths>
- [ ] **Tests added**: <test files, with paths>
- [ ] **Behavior**: <what a user/caller can now do that they couldn't before>
- [ ] **Behavior**: <what stops happening that used to>
- [ ] **Docs touched**: <files updated under docs/, if applicable>
- [ ] **Out of scope**: <explicit deferrals — what would be in scope but isn't>

## Evaluator commits to

> **qa-agent + code-reviewer-agent fill this.** Each Generator commitment above maps to a verification step. If you can't write a verification step for a commitment, the commitment is too vague — send it back.

| Generator commitment | Verification method | Pass criterion |
|---|---|---|
| Code change | `git diff main -- <files>` shows expected shape | Diff is surgical (no adjacent edits), passes lint |
| Tests added | `<test-runner> <test-files>` | All new tests pass; coverage of new code ≥ 80% |
| Behavior (positive) | <repro steps, ideally automated> | <observable result> |
| Behavior (negative) | <regression check, ideally automated> | <previous misbehavior absent> |
| Docs touched | grep for stale references; render markdown | No broken links; doc reflects new behavior |

## Eval task linkage

> If this work introduces a behavior worth grading continuously, link the eval task here. Add it to `evals/tasks/` and reference by id.

- Eval task id: `<domain>.<name>` (if applicable, else "n/a — one-off work")

## Risks / Cross-flow contracts

> Anything that touches another agent's surface, another module's contract, or a hot path. Be explicit.

- <e.g., "QA's `resolved` label flow depends on field X being populated; this PR keeps that contract">
- <e.g., "Touches the auto-mode classifier — re-run `/eval --cohort safety` post-merge">

## Sign-off

> Both parties sign before code is written. If scope changes mid-build, renegotiate and re-sign.

- Generator (dev-agent): <name/handle> · <YYYY-MM-DD>
- Evaluator (qa-agent): <name/handle> · <YYYY-MM-DD>
- Evaluator (code-reviewer-agent): <name/handle> · <YYYY-MM-DD>

---

## Append-only change log

> Every renegotiation goes here. New scope, new criteria, new sign-off lines.

- <YYYY-MM-DD> — Initial contract signed.
