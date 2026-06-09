#!/usr/bin/env bash
# tests/test_e2e_enhancement_archetypes.sh — Enhancement archetypes (Slice 3, Issue #69).
#
# Two distinct enhancement archetypes exercised in one file:
#
#   Archetype 2 — Enhancement WITH PRD gate (user-visible feature)
#     Operator request → PM writes PRD → PM applies `prioritized` + `priority:*`
#       → Dev writes design doc → Dev branch + worktree
#       → PR (Closes #<issue>, Refs #65) → CR LGTM → squash-merge --delete-branch
#       → REMOTE BRANCH DELETED → Worktree + local branch cleanup
#       → LOCAL WORKTREE + LOCAL BRANCH DELETED → QA single-pass → `resolved`
#
#   Archetype 3 — Enhancement WITHOUT PRD (chore / refactor)
#     PM applies `prioritized` directly (no PRD, no design doc)
#       → Dev branch + worktree → PR (Closes #<issue>)
#       → CR LGTM → squash-merge --delete-branch
#       → REMOTE BRANCH DELETED → Worktree + local branch cleanup
#       → LOCAL WORKTREE + LOCAL BRANCH DELETED → QA single-pass → `resolved`
#
# Post-merge invariants (operator's explicit requirement) are tagged:
#   # INVARIANT: remote-branch-deleted
#   # INVARIANT: local-worktree-branch-deleted
#
# Harness prerequisites:
#   tests/lib.sh       — PASS/FAIL counters + print_summary
#   tests/lib_e2e.sh   — sandbox + assertion helpers (merged in Slice 1, PR #73)
#
# CR note (carried forward from Slice 1 review of PR #73):
#   Use assert_pr_state <num> "merged" — NOT gh pr view --json mergedAt.
#   The stub stores merge time as merged_at (snake) but --json mergedAt
#   camelCase selector does not surface it.

# shellcheck source=./lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=./lib_e2e.sh
source "$(dirname "$0")/lib_e2e.sh"

e2e_setup

# ---------------------------------------------------------------------------
# Shared helper: simulate_prd_file <slug>
#
# Creates a docs/prd/PRD-<slug>.md file inside the sandbox work tree.
# Mirrors the real-project pattern where PM commits the PRD before Dev picks up.
# ---------------------------------------------------------------------------
simulate_prd_file() {
  local slug="$1"
  mkdir -p "$SANDBOX_WORK/docs/prd"
  cat > "$SANDBOX_WORK/docs/prd/PRD-$slug.md" <<EOF
# PRD: $slug

## Problem
Simulated PRD for E2E archetype test.

## Acceptance criteria
- Feature works end-to-end.
EOF
}

# ---------------------------------------------------------------------------
# Shared helper: simulate_design_doc <slug>
#
# Creates a docs/design/DESIGN-<slug>.md file inside the sandbox work tree.
# Mirrors the real-project pattern where Dev commits the design doc before
# implementation begins.
# ---------------------------------------------------------------------------
simulate_design_doc() {
  local slug="$1"
  mkdir -p "$SANDBOX_WORK/docs/design"
  cat > "$SANDBOX_WORK/docs/design/DESIGN-$slug.md" <<EOF
# Design: $slug

## Context
Simulated design doc for E2E archetype test.

## Approach
No-op implementation for testing purposes.
EOF
}

# ===========================================================================
# ARCHETYPE 2 — Enhancement WITH PRD gate
# ===========================================================================
echo "=========================================="
echo "  ARCHETYPE 2: Enhancement with PRD gate"
echo "=========================================="

# ---------------------------------------------------------------------------
# STAGE A2-1 — Issue filed
#
# Filed with `enhancement` + `backlog`. The `backlog` label signals PM has
# not yet triaged. `prioritized` must be absent at this point.
# ---------------------------------------------------------------------------
echo ""
echo "--- A2 Stage 1: issue filed (enhancement + backlog) ---"

A2_ISSUE_NUM="$(e2e_create_issue \
  "[ENH] Add dark-mode toggle to settings page" \
  "Operator request: users want a dark-mode option. User-visible feature — PRD required." \
  "enhancement,backlog")"

assert_label_present "enhancement"  "$A2_ISSUE_NUM" "issue"
assert_label_present "backlog"      "$A2_ISSUE_NUM" "issue"
assert_label_absent  "prioritized"  "$A2_ISSUE_NUM" "issue"
assert_issue_open "$A2_ISSUE_NUM"

# ---------------------------------------------------------------------------
# STAGE A2-2 — PRD exists
#
# PM writes the PRD before triaging. A PRD file must exist for user-visible
# features per SDLC Step 0.
# ---------------------------------------------------------------------------
echo ""
echo "--- A2 Stage 2: PRD exists ---"

A2_SLUG="dark-mode-toggle"
simulate_prd_file "$A2_SLUG"

# Assert the simulated PRD file exists in the sandbox
if [[ -f "$SANDBOX_WORK/docs/prd/PRD-$A2_SLUG.md" ]]; then
  printf '  PASS  PRD file docs/prd/PRD-%s.md exists\n' "$A2_SLUG"
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  PRD file docs/prd/PRD-%s.md missing\n' "$A2_SLUG"
  FAIL=$(( FAIL + 1 ))
fi

# ---------------------------------------------------------------------------
# STAGE A2-3 — PM triages
#
# PM removes `backlog`, adds `prioritized` + one `priority:*` label.
# Only PM applies these labels per label-discipline.
# ---------------------------------------------------------------------------
echo ""
echo "--- A2 Stage 3: PM triages (backlog removed, prioritized + priority:medium) ---"

e2e_remove_label "$A2_ISSUE_NUM" "issue" "backlog"
e2e_add_label    "$A2_ISSUE_NUM" "issue" "prioritized"
e2e_add_label    "$A2_ISSUE_NUM" "issue" "priority:medium"

assert_label_absent  "backlog"          "$A2_ISSUE_NUM" "issue"
assert_label_present "prioritized"      "$A2_ISSUE_NUM" "issue"
assert_label_present "priority:medium"  "$A2_ISSUE_NUM" "issue"

# ---------------------------------------------------------------------------
# STAGE A2-4 — Design doc exists
#
# Dev writes the design doc before coding, as required by SDLC Step 0 for
# user-visible features.
# ---------------------------------------------------------------------------
echo ""
echo "--- A2 Stage 4: design doc exists ---"

simulate_design_doc "$A2_SLUG"

if [[ -f "$SANDBOX_WORK/docs/design/DESIGN-$A2_SLUG.md" ]]; then
  printf '  PASS  design doc docs/design/DESIGN-%s.md exists\n' "$A2_SLUG"
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  design doc docs/design/DESIGN-%s.md missing\n' "$A2_SLUG"
  FAIL=$(( FAIL + 1 ))
fi

# ---------------------------------------------------------------------------
# STAGE A2-5 — Dev claims
#
# Dev applies `in-progress` and posts a pickup comment.
# `prioritized` label must be present (Dev may only pick up prioritized issues).
# ---------------------------------------------------------------------------
echo ""
echo "--- A2 Stage 5: Dev claims issue ---"

gh issue edit "$A2_ISSUE_NUM" --add-label "in-progress"
gh issue comment "$A2_ISSUE_NUM" --body "Picking this up — branch feat/$A2_ISSUE_NUM-dark-mode-toggle."

assert_label_present "in-progress"  "$A2_ISSUE_NUM" "issue"
assert_label_present "prioritized"  "$A2_ISSUE_NUM" "issue"
assert_comment_present "$A2_ISSUE_NUM" "issue" "Picking this up"

# ---------------------------------------------------------------------------
# STAGE A2-6 — Branch + worktree created
# ---------------------------------------------------------------------------
echo ""
echo "--- A2 Stage 6: branch + worktree created ---"

A2_BRANCH="feat/$A2_ISSUE_NUM-dark-mode-toggle"
A2_TASK_ID="enh-$A2_ISSUE_NUM"

e2e_create_worktree "$A2_TASK_ID" "$A2_BRANCH"

assert_worktree_exists "$A2_TASK_ID"
assert_branch_exists   "$A2_BRANCH"

# Push the branch to origin so merge can delete it later
git -C "$SANDBOX_WORK" push --quiet origin "$A2_BRANCH"

# ---------------------------------------------------------------------------
# STAGE A2-7 — PR opened
#
# PR body must contain:
#   Closes #<slice-issue>   — auto-closes the tracking issue on merge
#   Refs #65                — umbrella stays open until final slice
# Dev applies `in-review` label on the issue.
# ---------------------------------------------------------------------------
echo ""
echo "--- A2 Stage 7: PR opened (in-review, Closes #slice, Refs #65) ---"

A2_PR_BODY="$(printf 'Add dark-mode toggle to settings page.\n\nCloses #%s\nRefs #65' "$A2_ISSUE_NUM")"
A2_PR_NUM="$(e2e_create_pr \
  "feat(ui): add dark-mode toggle to settings page" \
  "$A2_PR_BODY" \
  "$A2_BRANCH" \
  "main")"

gh issue edit "$A2_ISSUE_NUM" --add-label "in-review"

assert_label_present "in-review"             "$A2_ISSUE_NUM" "issue"
assert_pr_state      "$A2_PR_NUM" "open"
assert_pr_body_contains "$A2_PR_NUM" "Closes #$A2_ISSUE_NUM"
assert_pr_body_contains "$A2_PR_NUM" "Refs #65"

# ---------------------------------------------------------------------------
# STAGE A2-8 — CR posts LGTM
#
# Code Reviewer posts a top-level LGTM comment as required by SDLC Step 6.
# ---------------------------------------------------------------------------
echo ""
echo "--- A2 Stage 8: CR posts LGTM ---"

e2e_add_comment "$A2_PR_NUM" "pr" "LGTM — design doc present, implementation matches spec."

assert_comment_present "$A2_PR_NUM" "pr" "LGTM"

# ---------------------------------------------------------------------------
# STAGE A2-9 — CR merges with --delete-branch
#
# CR runs: gh pr merge <N> --squash --delete-branch
# Expect:
#   - PR state == "merged"
#   - Issue auto-closed (Closes #N in body)
#   - Remote branch deleted  ← INVARIANT: remote-branch-deleted
#   - in-review label removed from issue
# ---------------------------------------------------------------------------
echo ""
echo "--- A2 Stage 9: CR merges (squash --delete-branch) ---"

gh pr merge "$A2_PR_NUM" --squash --delete-branch

# PR is merged (use assert_pr_state — not gh pr view --json mergedAt; see CR note)
assert_pr_state "$A2_PR_NUM" "merged"

# Issue auto-closed via Closes #N in PR body
assert_issue_closed "$A2_ISSUE_NUM"

# INVARIANT: remote-branch-deleted
# Remote branch must be gone immediately after merge with --delete-branch.
assert_remote_branch_deleted "$A2_BRANCH"  # INVARIANT: remote-branch-deleted

# CR housekeeping: remove in-review after merge
gh issue edit "$A2_ISSUE_NUM" --remove-label "in-review"
assert_label_absent "in-review" "$A2_ISSUE_NUM" "issue"

# ---------------------------------------------------------------------------
# STAGE A2-10 — Worktree cleanup (post-merge)
#
# After merge, remote is gone but local worktree + branch still exist.
# Dev performs mandatory cleanup:
#   git worktree remove .worktrees/<task-id>
#   git branch -D <branch>
#
# BEFORE cleanup: worktree dir + local branch still present.
# AFTER cleanup: both gone.  ← INVARIANT: local-worktree-branch-deleted
# ---------------------------------------------------------------------------
echo ""
echo "--- A2 Stage 10: post-merge worktree cleanup ---"

# Before cleanup: local state still exists (remote is already gone)
assert_worktree_exists "$A2_TASK_ID"
assert_branch_exists   "$A2_BRANCH"

# Dev performs mandatory post-merge cleanup
e2e_remove_worktree "$A2_TASK_ID"

# INVARIANT: local-worktree-branch-deleted
assert_worktree_removed "$A2_TASK_ID"  # INVARIANT: local-worktree-branch-deleted
assert_branch_deleted   "$A2_BRANCH"   # INVARIANT: local-worktree-branch-deleted

# ---------------------------------------------------------------------------
# STAGE A2-11 — QA single-pass
#
# QA runs the acceptance criteria from the PRD, verifies the feature works,
# and applies `resolved`. Labels retained post-QA:
#   - `resolved` added
#   - `enhancement` retained (audit trail)
#   - Issue remains closed
# ---------------------------------------------------------------------------
echo ""
echo "--- A2 Stage 11: QA single-pass (resolved applied, enhancement retained) ---"

gh issue edit "$A2_ISSUE_NUM" --add-label "resolved"

assert_label_present "resolved"    "$A2_ISSUE_NUM" "issue"
assert_label_present "enhancement" "$A2_ISSUE_NUM" "issue"
assert_issue_closed  "$A2_ISSUE_NUM"


# ===========================================================================
# ARCHETYPE 3 — Enhancement WITHOUT PRD (chore / refactor)
# ===========================================================================

# Reset stub state so issue/PR numbers are independent across archetypes.
e2e_reset_state

echo ""
echo "=========================================="
echo "  ARCHETYPE 3: Enhancement without PRD (chore/refactor)"
echo "=========================================="

# ---------------------------------------------------------------------------
# STAGE A3-1 — Issue filed
#
# Filed as enhancement + backlog (same as Archetype 2). There is no PRD
# for chores/refactors — they go straight from triage to Dev.
# ---------------------------------------------------------------------------
echo ""
echo "--- A3 Stage 1: issue filed (enhancement + backlog) ---"

A3_ISSUE_NUM="$(e2e_create_issue \
  "[ENH] Refactor auth module to use shared token-validator utility" \
  "No user-visible behavior change. Chore/refactor — PRD and design doc not required." \
  "enhancement,backlog")"

assert_label_present "enhancement"  "$A3_ISSUE_NUM" "issue"
assert_label_present "backlog"      "$A3_ISSUE_NUM" "issue"
assert_label_absent  "prioritized"  "$A3_ISSUE_NUM" "issue"
assert_issue_open "$A3_ISSUE_NUM"

# ---------------------------------------------------------------------------
# STAGE A3-2 — PM triages directly (no PRD)
#
# For chores/refactors, PM applies `prioritized` + `priority:*` directly.
# No PRD file and no design doc are required or expected.
# ---------------------------------------------------------------------------
echo ""
echo "--- A3 Stage 2: PM triages directly (no PRD, no design doc) ---"

e2e_remove_label "$A3_ISSUE_NUM" "issue" "backlog"
e2e_add_label    "$A3_ISSUE_NUM" "issue" "prioritized"
e2e_add_label    "$A3_ISSUE_NUM" "issue" "priority:low"

assert_label_absent  "backlog"         "$A3_ISSUE_NUM" "issue"
assert_label_present "prioritized"     "$A3_ISSUE_NUM" "issue"
assert_label_present "priority:low"    "$A3_ISSUE_NUM" "issue"

# Confirm no PRD file exists for this chore — absence is the intended state
if [[ ! -f "$SANDBOX_WORK/docs/prd/PRD-auth-refactor.md" ]]; then
  printf '  PASS  no PRD file for chore issue (expected for refactor)\n'
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  unexpected PRD file found for chore issue\n'
  FAIL=$(( FAIL + 1 ))
fi

# Confirm no design doc exists for this chore — absence is the intended state
if [[ ! -f "$SANDBOX_WORK/docs/design/DESIGN-auth-refactor.md" ]]; then
  printf '  PASS  no design doc for chore issue (expected for refactor)\n'
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  unexpected design doc found for chore issue\n'
  FAIL=$(( FAIL + 1 ))
fi

# ---------------------------------------------------------------------------
# STAGE A3-3 — Dev claims
# ---------------------------------------------------------------------------
echo ""
echo "--- A3 Stage 3: Dev claims issue ---"

gh issue edit "$A3_ISSUE_NUM" --add-label "in-progress"
gh issue comment "$A3_ISSUE_NUM" --body "Picking this up — branch refactor/$A3_ISSUE_NUM-auth-token-validator."

assert_label_present "in-progress"  "$A3_ISSUE_NUM" "issue"
assert_label_present "prioritized"  "$A3_ISSUE_NUM" "issue"
assert_comment_present "$A3_ISSUE_NUM" "issue" "Picking this up"

# ---------------------------------------------------------------------------
# STAGE A3-4 — Branch + worktree created
# ---------------------------------------------------------------------------
echo ""
echo "--- A3 Stage 4: branch + worktree created ---"

A3_BRANCH="refactor/$A3_ISSUE_NUM-auth-token-validator"
A3_TASK_ID="chore-$A3_ISSUE_NUM"

e2e_create_worktree "$A3_TASK_ID" "$A3_BRANCH"

assert_worktree_exists "$A3_TASK_ID"
assert_branch_exists   "$A3_BRANCH"

# Push the branch to origin so merge can delete it later
git -C "$SANDBOX_WORK" push --quiet origin "$A3_BRANCH"

# ---------------------------------------------------------------------------
# STAGE A3-5 — PR opened
#
# PR body must contain Closes #<issue>.
# No umbrella reference (this is a standalone chore, not part of a multi-PR
# umbrella — single Closes suffices).
# ---------------------------------------------------------------------------
echo ""
echo "--- A3 Stage 5: PR opened (in-review, Closes #issue) ---"

A3_PR_BODY="$(printf 'Extract shared token-validator utility; no behavior change.\n\nCloses #%s' "$A3_ISSUE_NUM")"
A3_PR_NUM="$(e2e_create_pr \
  "refactor(auth): extract shared token-validator utility" \
  "$A3_PR_BODY" \
  "$A3_BRANCH" \
  "main")"

gh issue edit "$A3_ISSUE_NUM" --add-label "in-review"

assert_label_present "in-review"              "$A3_ISSUE_NUM" "issue"
assert_pr_state      "$A3_PR_NUM" "open"
assert_pr_body_contains "$A3_PR_NUM" "Closes #$A3_ISSUE_NUM"

# ---------------------------------------------------------------------------
# STAGE A3-6 — CR posts LGTM
# ---------------------------------------------------------------------------
echo ""
echo "--- A3 Stage 6: CR posts LGTM ---"

e2e_add_comment "$A3_PR_NUM" "pr" "LGTM — no behavior change confirmed, existing tests still green."

assert_comment_present "$A3_PR_NUM" "pr" "LGTM"

# ---------------------------------------------------------------------------
# STAGE A3-7 — CR merges with --delete-branch
#
# Same merge mechanic as Archetype 2.
# ---------------------------------------------------------------------------
echo ""
echo "--- A3 Stage 7: CR merges (squash --delete-branch) ---"

gh pr merge "$A3_PR_NUM" --squash --delete-branch

assert_pr_state "$A3_PR_NUM" "merged"
assert_issue_closed "$A3_ISSUE_NUM"

# INVARIANT: remote-branch-deleted
assert_remote_branch_deleted "$A3_BRANCH"  # INVARIANT: remote-branch-deleted

# CR housekeeping
gh issue edit "$A3_ISSUE_NUM" --remove-label "in-review"
assert_label_absent "in-review" "$A3_ISSUE_NUM" "issue"

# ---------------------------------------------------------------------------
# STAGE A3-8 — Worktree cleanup (post-merge)
# ---------------------------------------------------------------------------
echo ""
echo "--- A3 Stage 8: post-merge worktree cleanup ---"

# Before cleanup: local state still exists
assert_worktree_exists "$A3_TASK_ID"
assert_branch_exists   "$A3_BRANCH"

# Dev performs mandatory post-merge cleanup
e2e_remove_worktree "$A3_TASK_ID"

# INVARIANT: local-worktree-branch-deleted
assert_worktree_removed "$A3_TASK_ID"  # INVARIANT: local-worktree-branch-deleted
assert_branch_deleted   "$A3_BRANCH"   # INVARIANT: local-worktree-branch-deleted

# ---------------------------------------------------------------------------
# STAGE A3-9 — QA single-pass
#
# QA verifies no regressions were introduced by the refactor, then applies
# `resolved`. Same terminal state as Archetype 2.
# ---------------------------------------------------------------------------
echo ""
echo "--- A3 Stage 9: QA single-pass (resolved applied, enhancement retained) ---"

gh issue edit "$A3_ISSUE_NUM" --add-label "resolved"

assert_label_present "resolved"    "$A3_ISSUE_NUM" "issue"
assert_label_present "enhancement" "$A3_ISSUE_NUM" "issue"
assert_issue_closed  "$A3_ISSUE_NUM"

# ===========================================================================
print_summary
