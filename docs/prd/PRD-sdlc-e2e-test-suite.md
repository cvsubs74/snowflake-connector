# PRD: SDLC E2E Test Suite

## Problem

The agent team enforces the SDLC through a combination of written contracts (agent `.md` files, `SDLC.md`), six mechanical hooks, and operator briefs. None of these verify that the full workflow — from issue creation through label transitions, branch/worktree lifecycle, PR open/merge, and post-merge cleanup — behaves correctly end-to-end. Today the gap surfaces as recurring operational pain:

- The team-lead playbook documents that Dev worktrees and local branches persist after merge across multiple sessions (PRs #56, #58, #59–#61). Hook 6 enforces `--delete-branch` at command time for the remote branch, but nothing enforces local worktree cleanup.
- Label drift (stale `in-progress`/`in-review` after merge) surfaces as noise in `bin/team-status.sh` output and requires manual cleanup.
- Cross-agent invariants (e.g., "after PM applies `prioritized`, the issue has exactly one `priority:*`") are described in prose but not mechanically asserted.

A concrete scenario: an operator runs `bash tests/run.sh` today. All 110+ hook-unit tests pass. But no test verifies that running through the full bug-fix archetype — file issue, Dev branches in worktree, opens PR with `in-review`, CR merges with `--delete-branch`, local worktree is gone — leaves the system in the expected state. That workflow gap is the pain this PRD addresses.

## Users

- **Team Lead** — needs confidence that the SDLC is enforced end-to-end before briefing specialists into parallel sessions.
- **Dev agents** — benefit from fast feedback when a workflow step is accidentally skipped (local worktree not cleaned up, label left on issue post-merge).
- **Operators** — need a single `bash tests/run.sh` invocation that covers both hook mechanics and full-workflow invariants.
- **PR authors and reviewers** — benefit from a test that catches the "CR posts LGTM but skips the merge step" anti-pattern before it becomes an issue.

## Success metrics

- `bash tests/run.sh` covers all nine SDLC archetypes defined in the Scope section.
- Every archetype test asserts discrete state at each workflow stage (pre-PR, PR-open, post-merge, post-cleanup).
- The local-worktree cleanup assertion is a first-class test case: after simulated merge, `.worktrees/<task-id>` does not exist and the local branch is gone.
- Zero new test files require network access (GitHub API) to pass — the harness runs hermetically in CI with no `gh` credential.
- The test suite runs in under 60 seconds on a developer laptop.
- `bin/team-status.sh` output after a simulated full archetype run shows clean state (no stale labels, no stale worktrees).

## What exists today

The current `tests/` suite covers:

| File | What it covers |
|---|---|
| `test_hooks.sh` | Unit tests for all 6 hooks. Hook inputs → expected exit codes / stderr. ~110 cases. |
| `test_consistency.sh` | Cross-document drift checks: SDLC label table == label-discipline SKILL.md; hook filesystem == settings.json == README inventory; agent topology == 8 expected agents. |
| `test_repo.sh` | Repo structure sanity: JSON validity, hook executability, required docs present, `bash -n` syntax check on all scripts. |

What is NOT covered:

- No full-workflow archetype test (multi-step state machine through a complete SDLC path).
- No assertion that local worktrees are cleaned up after merge.
- No assertion that label state at each workflow stage is correct (e.g., `in-review` removed when PR closes, `resolved` only after two-pass, no `backlog` on a bug).
- No assertion that the `Refs #N` vs `Closes #N` discipline is followed for multi-slice umbrella issues.
- No assertion that the `in-review` gate (Hook 3) and `--delete-branch` gate (Hook 6) are both respected in a simulated end-to-end merge scenario.

**What hooks already enforce (no new test coverage needed for these invariants):**

- Hook 1: direct push to `main` is blocked.
- Hook 2: restricted label ownership is blocked for non-owner agents.
- Hook 3: `gh pr merge` without `in-review` label is blocked.
- Hook 5: `gh pr create` without `Closes #N` emits a warning.
- Hook 6: `gh pr merge` without `--delete-branch` is blocked.

The new suite covers the inter-step state invariants that hooks cannot express — filesystem state, label combinations, worktree existence.

## Scope

- Nine workflow archetypes as defined below, each with discrete state assertions per stage.
- A first-class test for the operator-called-out invariant: local worktree cleanup after merge.
- A new hook (Hook 7) if the PRD-scoped analysis concludes one is needed for local-worktree enforcement (see Risks).
- Test harness infrastructure: a sandbox git repo + scripted fake `gh` replacement that simulates label queries without network access (see Harness Shape section).
- Integration of new test files into `tests/run.sh` (auto-discovery is already in place).

## Out of scope

- Agent-behavior tests (testing what an LLM outputs given a brief — not testable deterministically).
- LLM-output fidelity tests (e.g., "does the PM agent write a correct PRD?").
- Performance or load tests.
- UI/visual regression tests (this repo has no deployed UI surface).
- GitHub Actions CI configuration changes (the test suite must be hermetic-first; CI integration is a follow-on).
- Testing the `gh auth login` flow or any live GitHub credential management.
- Full integration with a live ephemeral GitHub repository (this is an option in the Harness Shape section but is not the recommended approach — see below).

## Archetypes to cover

Each archetype maps to one child issue (slice). The state-assertion model defines the discrete states the workflow passes through and what must be true at each checkpoint.

### Archetype 1 — Bug fast-path

Flow: operator files bug → Triage enriches it → Dev branches in worktree + applies `in-progress` → Dev opens PR with `in-review` → CR merges with `--delete-branch` → post-merge: worktree gone, branch gone, labels clean, issue auto-closed → QA two-pass → `resolved` applied.

State assertions:
- After bug filed: issue has `bug` label, does NOT have `backlog`, does NOT have `prioritized`.
- After Dev picks up: `in-progress` on issue, worktree exists at `.worktrees/<task-id>`, local branch exists.
- After PR open: `in-review` on issue/PR, `in-progress` may remain.
- After CR merges (with `--delete-branch`): PR state is `MERGED`, issue is closed (via `Closes #N` in body), local worktree at `.worktrees/<task-id>` does NOT exist, local branch does NOT exist, remote branch does NOT exist.
- After QA two-pass: `resolved` label on issue. No `bug` label remains? (Note: `bug` label is not removed by convention — `resolved` is the terminal state signal, not label removal. Assert `resolved` is present.)

Hook coverage overlap: Hook 3 (`in-review` required before merge), Hook 6 (`--delete-branch` required) are already unit-tested. New assertion: local worktree + branch cleanup.

### Archetype 2 — Enhancement with PRD gate (frontend)

Flow: operator requests feature → PM writes PRD → PM files umbrella issue (`pm,backlog`) → Designer reviews PRD → Designer posts "Design Approved" → PM slices into child issues (`prioritized,priority:medium`) → Dev creates worktree, writes design doc, implements → PR opens with `in-review` → Designer posts "Design Approved" on PR → CR merges → DevOps no-op (no deployable service) → QA single-pass against PRD acceptance criteria → `resolved`.

State assertions:
- After PRD filed: umbrella issue has `pm,backlog`, no `prioritized`.
- After PM slices: child issues have `enhancement,prioritized,priority:*`, each `Refs #<umbrella>`, final slice has `Closes #<umbrella>`.
- After Dev opens PR: `in-review` on PR, design doc exists at `docs/design/DESIGN-<topic>.md`.
- After Designer gate: "Design Approved" comment present on PR before CR may merge.
- After final slice merges: umbrella issue is closed (via `Closes #N` on final PR).
- After QA: `resolved` on issue.

Hook coverage overlap: Hook 5 (`Closes #N` warning). New assertions: umbrella issue closure discipline, Designer gate convention, design doc presence.

### Archetype 3 — Enhancement without PRD (chore / refactor)

Flow: Dev files chore issue (`enhancement,backlog`) → PM triages to `prioritized,priority:low` → Dev branches, makes change, opens PR with no PRD/design doc required → CR merges → QA single-pass.

State assertions:
- Issue type is `enhancement` (not `bug`), starts with `backlog`.
- After PM triage: `prioritized` + exactly one `priority:*`, `backlog` removed.
- After Dev opens PR: PR body contains `Closes #N` (or warning fired via Hook 5).
- After merge: issue closed, no stale labels.

### Archetype 4 — Multi-PR umbrella (Refs / Closes discipline)

Flow: PM files umbrella → PM creates N slices → Dev works slices in sequence → slices 1..N-1 use `Refs #<umbrella>`, slice N uses `Closes #<umbrella>` → after slice N merges, umbrella closes.

State assertions:
- After each non-final slice merges: umbrella issue is still OPEN.
- After final slice merges: umbrella issue is CLOSED.
- Each child PR body contains either `Refs #<umbrella>` or `Closes #<umbrella>` (never both, never neither).
- Hook 5 warning NOT triggered on any child (all have auto-close keyword or `Refs` — the test must verify that `Refs` still triggers the warning, as Hook 5 treats it as incomplete; document that this is intentional per the `Refs` discipline).

### Archetype 5 — Hotfix path

Flow: operator-reported regression in production → Dev branches as `fix/<N>-<slug>` directly off `main` (no PM triage, no PRD, no backlog) → PR opened immediately → CR fast-path review → merge with `--delete-branch` → DevOps deploy (no-op for this repo) → QA two-pass.

State assertions:
- No `backlog` or `prioritized` label; issue has `bug`.
- Branch name matches `fix/` prefix.
- After merge: same worktree/branch cleanup assertions as Archetype 1.

### Archetype 6 — Operator-initiated bug with Triage verification cycle

Flow: operator reports symptom in a message → Triage runs 60–90s sprint → files enriched `bug` issue → Dev fixes → Triage pings operator → operator confirms → Triage hands to QA → QA two-pass → `resolved`.

State assertions:
- Bug issue has `bug` label, NOT `backlog`.
- After Dev merges fix: Triage comment present on issue pinging operator.
- `resolved` is applied only after operator confirms AND QA completes two-pass.
- Issue is NOT `resolved` before operator confirmation.

### Archetype 7 — Designer-gated frontend PR (convention-only)

Flow: Dev opens PR touching a frontend path → CR waits for Designer to post "Design Approved" before merging → Designer posts approval → CR merges.

State assertions:
- CR must NOT merge before "Design Approved" comment is present (convention-only; no hook enforces this — test asserts the convention, not a mechanical block).
- After "Design Approved" comment posted: CR merge proceeds.
- After "Design Blocked" comment: CR posts CHANGES REQUESTED, Dev iterates.

Note: Hook 7 (documented upgrade path in SDLC Step 5 and team-lead playbook) would mechanically enforce this. If Hook 7 is built as part of this effort, the test for it belongs here.

### Archetype 8 — Deploy + DevOps rollback (no-service short-circuit)

Flow: change merges → CR posts FINAL CLOSER with `@devops-agent — please deploy` → DevOps confirms no deployable service → no-op, deploy confirmation comment posted → QA proceeds.

State assertions:
- DevOps cold-start reports "No deployable services — DevOps is a no-op."
- After DevOps posts no-op confirmation: QA picks up for post-merge verification.
- No deploy script invoked (assert no side effects).

### Archetype 9 — CR rejects breaking cross-flow contract change

Flow: Dev opens PR that modifies a shared contract (e.g., a hook's stdin schema or a label set) without updating all consumers → CR reviews → detects single-side contract change → posts CHANGES REQUESTED → Dev iterates, updates both sides → CR re-reviews → LGTM → merge.

State assertions:
- After initial CHANGES REQUESTED: PR status is not merged, issue retains `in-review`.
- After Dev pushes updated commits: CR re-reviews (new commit SHA exists on PR).
- After LGTM on the corrected PR: merge proceeds normally.
- Cross-flow: both sides of the contract are updated in the diff (e.g., hook script + test + README inventory).

## State-assertion model

For every archetype, the test harness verifies state at these checkpoints:

| Checkpoint | What to assert |
|---|---|
| Issue created | Labels match expected set, no forbidden labels present |
| Dev picks up | `in-progress` on issue, worktree exists at `.worktrees/<task-id>`, branch exists locally |
| PR opened | `in-review` on PR, PR body contains `Closes #N` or `Refs #N` as appropriate |
| Pre-merge gate | Hook 3 (`in-review` required) would allow; Hook 6 (`--delete-branch` required) would allow |
| After merge | PR state = MERGED, issue state = CLOSED (if `Closes`), remote branch deleted, local branch deleted, local worktree removed |
| Post-merge QA | `resolved` label on issue, no stale `in-progress`/`in-review` |

The **local worktree cleanup assertion** (after merge, `.worktrees/<task-id>` does not exist) is a first-class assertion in every archetype that involves Dev creating a worktree. This directly addresses the operator's stated invariant and the recurring gap documented in the team-lead playbook.

## Operator's invariant: local worktree cleanup

The operator explicitly stated: "When a PR is merged, the local worktree for the feature branch and the remote should be deleted."

Current state:
- **Remote branch**: Hook 6 enforces `--delete-branch` at `gh pr merge` command time. Server-side `delete_branch_on_merge=true` is a safety net. These are well-covered.
- **Local worktree**: NOT enforced mechanically. Dev agent docs specify `git worktree remove .worktrees/<task-id>` as a post-merge step, but the team-lead playbook documents that Dev agents consistently skip this when their session ends immediately after merge confirmation (sessions across PRs #56, #58, #59–#61 all left stale worktrees).

Two mitigations to scope in this PRD:

1. **Test assertion (required in this PRD):** Every archetype test that involves a worktree must assert that the worktree is gone after the simulated merge + cleanup step. This makes the cleanup a verifiable invariant rather than a convention.
2. **Hook 7 — local worktree cleanup hook (enhancement, scoped as a child issue):** A `PostToolUse` or `Stop` hook that, when `gh pr merge` succeeds, enumerates `.worktrees/` directories whose branch names match the merged PR's branch and invokes `git worktree remove`. This would enforce cleanup mechanically even when Dev agents skip the manual step. This is the "Hook 7" upgrade path referenced in `SDLC.md` Step 5 note and the team-lead playbook. Scope as a separate child issue (`enhancement,backlog`).

## Harness shape

Three approaches; one recommendation.

### Option A — Bash + sandbox git repo + fake `gh` stub (recommended)

Create a temporary git repo per test run, script all `gh` operations through a stub that mimics `gh issue create`, `gh pr create`, `gh pr merge` output and exit codes while writing state to a local JSON file. All assertions are filesystem and local-git assertions.

Pros:
- Hermetic: no network, no GitHub credentials, runs in CI without secrets.
- Fast: < 5 seconds per archetype.
- Faithful to the things we actually care about: label state (tracked in the stub), branch existence, worktree existence, hook behavior.
- Extends the existing test harness pattern (`tests/lib.sh`, `run_case`).
- Consistent with the project's shell-first approach.

Cons:
- The `gh` stub is not real `gh` — some behaviors may diverge (e.g., auto-close on merge triggered by `Closes #N` is a server-side GitHub feature; the stub must simulate it).
- High maintenance if `gh` CLI changes its output format.
- Does not test real GitHub API interactions.

Mitigation for the auto-close simulation: the stub, on `gh pr merge`, reads the PR body from the stub state, finds `Closes #N`, and marks the corresponding issue as closed — faithfully simulating GitHub's server-side behavior.

### Option B — Bash + ephemeral throwaway GitHub repo

Create a real GitHub repo per test run using `gh repo create --private --clone`, run real `gh` commands, assert real GitHub state, delete the repo on cleanup.

Pros:
- Tests real `gh` behavior, including auto-close.
- No stub drift risk.

Cons:
- Requires `gh` auth credentials in CI.
- Slow: GitHub API calls add 2–5s per step.
- Consumes org repo quota (or personal repo clutter if not cleaned up promptly).
- Rate limits can make the suite flaky under parallel runs.
- Layer 2 mania risk: adding real network dependencies to a suite that is currently hermetic is a complexity ratchet.

### Option C — Git-only state (local-side invariants only)

Assert only the local filesystem invariants: worktree existence, branch existence, hook behavior on simulated payloads. Skip PR/label semantics entirely.

Pros:
- Trivially hermetic.
- Zero stub maintenance.

Cons:
- Does not cover the label-state invariants (which are the second major gap after worktree cleanup).
- Does not cover `Closes #N` / `Refs #N` discipline.
- Leaves 70% of the state machine unverified.

### Recommendation: Option A (Bash + sandbox git repo + fake `gh` stub)

Option A minimizes Layer 2 mania risk (no new network dependencies) while still catching real regressions in label state, worktree cleanup, and inter-step invariants. The stub is a modest investment; the payoff is a hermetic, fast, comprehensive suite. The auto-close simulation is the only non-trivial stub behavior, and it is well-understood.

Per User Sovereignty: this is a recommendation. The operator should confirm before Dev implements it. If the operator prefers real GitHub integration (Option B) for higher fidelity, Dev can implement that instead.

## Slicing plan

This is a multi-PR effort. The umbrella issue tracks all slices. Slicing order is designed so each slice ships independently useful coverage.

- **Slice 1 — Harness infrastructure**: `tests/lib_e2e.sh` (sandbox git repo helpers, fake `gh` stub), integration into `tests/run.sh`. No archetype tests yet — just the harness. Refs umbrella.
- **Slice 2 — Bug fast-path archetype (Archetype 1)**: Full test for the bug fast-path, including the local worktree cleanup assertion. This is the operator's first-priority invariant. Refs umbrella.
- **Slice 3 — Enhancement archetypes (Archetypes 2 + 3)**: PRD gate + chore/refactor, including Designer gate convention assertion and design doc presence check. Refs umbrella.
- **Slice 4 — Multi-PR umbrella + hotfix archetypes (Archetypes 4 + 5)**: Refs/Closes discipline + hotfix path. Refs umbrella.
- **Slice 5 — Operator-initiated bug + Designer gate + DevOps no-op + CR contract rejection (Archetypes 6–9)**: Remaining four archetypes. Closes umbrella.
- **Slice 6 (optional) — Hook 7 local-worktree cleanup hook**: If the operator confirms this is in scope. Filed as a separate `enhancement,backlog` child issue; not part of the test suite slices above.

Each slice ships a complete archetype's coverage, not a half-built harness across all archetypes (per Boil the Lake — each merged PR leaves the suite more useful than before).

## Open questions

- **Harness approach confirmation**: Does the operator prefer Option A (hermetic Bash stub, recommended) or Option B (live GitHub repo, higher fidelity)? Dev will not start on Slice 1 until this is confirmed.
- **Hook 7 scope**: Is the local-worktree cleanup hook (Hook 7) in scope for this effort, or should it be filed as a separate backlog item after the test suite ships? The playbook documents it as a known gap; the PRD can include it as a child issue.
- **Designer gate enforcement**: SDLC Step 5 explicitly notes "Hook 7 to enforce this mechanically is the documented upgrade path." Should the Designer-gate enforcement hook be scoped here alongside the worktree-cleanup hook, or separately?

## Risks

- **Stub drift**: The fake `gh` stub will need maintenance if `gh` CLI output format changes. Mitigate by keeping the stub minimal (only the operations the tests need) and adding a `test_stub_contract.sh` to detect drift.
- **Archetype-test brittleness**: Full-workflow tests are harder to debug than unit tests. Keep each archetype test short (~50 lines), single-responsibility, and with clear failure messages. Follow the existing `run_case` pattern.
- **Scope creep to Option B**: Once a hermetic suite exists, there will be pressure to add live-GitHub tests "just for this one thing." Resist. If live tests are ever needed, they belong in a separate `tests/integration/` directory with explicit CI-credentials documentation.
- **Hook 7 complexity**: Auto-cleanup on merge could create false positives (e.g., cleaning up a worktree that the Dev agent is still using in a parallel session). The hook must be conservative: only clean up worktrees whose branch matches the merged PR and where no active Claude Code session is using the worktree.
- **Two-pass QA simulation**: Faithfully simulating the §TWO-PASS rule in a hermetic harness requires the stub to distinguish "first verification run" from "second run." This is low complexity but must be explicitly scoped in Slice 2/3.
