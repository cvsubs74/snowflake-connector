---
name: contract-negotiation
description: Use when starting any non-trivial feature or bug, before writing implementation code. Walks dev-agent and qa-agent + code-reviewer-agent through writing a sprint contract under docs/contracts/. Encodes the Generator/Evaluator handoff pattern from the Anthropic harness-design post.
---

# contract-negotiation — Generator ↔ Evaluator sprint contract

The single best defense against "done means different things to different agents" is to **write down what done means, before coding, in a place both parties have signed.**

## When to use

- New feature with PRD attached → always.
- Bug fix touching more than one file → always.
- Refactor with observable behavior change → always.
- Trivial fix (typo, one-line change) → skip; the PR description is the contract.

## The protocol

**Step 1 — Generator drafts the contract.**

dev-agent, before touching implementation code on the working branch:

```bash
cp docs/contracts/_template.md docs/contracts/<issue-number>-<slug>.md
```

Fill the "Generator commits to" section. Be specific:

- ❌ "Add validation to the user form"
- ✅ "Add `validate_email(str) -> Result<Email, ValidationError>` in `src/auth/validators.rs`; reject inputs without `@`, empty local part, or domain >253 chars; existing `auth/test_validators.rs` gets 6 new cases"

Each commitment must be observable. If you can't say "this file at this path will contain this thing," the commitment is too vague.

**Step 2 — Evaluator writes verification steps.**

qa-agent + code-reviewer-agent (working from the same draft):

For each Generator commitment, fill a row in the verification table. If you can't write a verification step, the commitment is too vague → kick back to Generator.

Example:

| Generator commits | Verification | Pass criterion |
|---|---|---|
| `validate_email` rejects no-`@` strings | `cargo test auth::validators::test_no_at_sign` | Test passes; pre-existing tests still pass |

**Step 3 — Both sign.**

In the Sign-off block, add names + date. Commit the contract to the working branch as its own commit:

```bash
git add docs/contracts/<issue-number>-<slug>.md
git commit -m "contract: <issue-number> <slug>"
```

**Step 4 — Implement against the contract.**

Generator's PR must close every Generator-side checkbox. Evaluator's verification runs through every row in the table before approving.

**Step 5 — If scope changes, renegotiate.**

Don't silently expand. Add a new entry to the append-only change log; both parties re-sign.

## What this skill does NOT replace

- **The PRD.** PRD is the *why*; the contract is the *what*.
- **The design doc.** Design doc is *how* (architecture, data model); the contract is *acceptance*.
- **Code review.** Review checks correctness against the *codebase*; the contract checks shippability against the *promise*.

## Why this matters

From the harness-design post:

> "Generator and Evaluator negotiate testable acceptance criteria before coding starts."

Without a contract, the Evaluator either (a) is overly strict and blocks shippable work, or (b) is overly lenient and lets in vague work. The contract collapses the negotiation cost from "every PR review" to "once per feature."

Skipping the contract is allowed — but only for trivial work. If you find yourself skipping it on a `priority:high` enhancement, you're trading hours of review churn for thirty seconds of upfront work. Don't.

## Related

- `docs/contracts/README.md` — the directory's purpose and lifecycle rules
- `docs/contracts/_template.md` — the template
- `eval-runner` skill — most contract criteria become eval tasks once stable
