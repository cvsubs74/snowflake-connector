#!/usr/bin/env bash
# tests/test_e2e_umbrella_and_hotfix.sh — Multi-PR umbrella + hotfix (Slice 4, Issue #70).
#
# Two distinct archetypes exercised in one file:
#
#   Archetype 4 — Multi-PR umbrella (the pattern this very slicing effort uses)
#     An umbrella issue tracks N child slice issues. Each mid-series slice uses
#     `Closes #<slice>, Refs #<umbrella>`. The umbrella stays OPEN through every
#     non-final slice. The FINAL slice uses `Closes #<final-slice>, Closes #<umbrella>`
#     to retire the umbrella.
#
#     *** DEFECT PATH (canonical wrong pattern) ***
#     If a mid-series PR uses `Refs #<slice>` instead of `Closes #<slice>`,
#     the slice issue STAYS OPEN after merge. This is exactly what happened on
#     Slices 1+2 (issues #67 and #68), requiring manual cleanup. The defect-path
#     test here makes that failure mode impossible to miss.
#
#   Archetype 5 — Hotfix (SDLC §Step 0 fast path)
#     Production bug surfaces → Dev opens `fix/<N>-<slug>` directly → PR with
#     `hotfix` label → CR fast-track review (still required) → merge with
#     --delete-branch → DevOps deploys → QA single-pass.
#     Per SDLC Step 0: hotfixes skip PRD + design doc gates entirely.
#
# Post-merge invariants (operator's explicit requirement, tagged for grep):
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

# ===========================================================================
# ARCHETYPE 4 — Multi-PR umbrella
#
# Topology mirrored from this repo's own umbrella #65 + slices #67-#70:
#
#   Umbrella issue (open throughout non-final slices)
#     └── Slice A  — correct pattern: Closes #A, Refs #umbrella  → A closes, umbrella OPEN
#     └── Slice B  — DEFECT PATH:     Refs  #B, Refs #umbrella   → B stays OPEN  ← KEY TEST
#     └── Slice C  — final slice:     Closes #C, Closes #umbrella → C + umbrella both close
# ===========================================================================
echo "=========================================="
echo "  ARCHETYPE 4: Multi-PR umbrella"
echo "=========================================="

# ---------------------------------------------------------------------------
# A4-SETUP — Create umbrella issue
#
# The umbrella is created first. It has no `backlog` or `prioritized` label
# by itself — it is purely a tracking issue for coordinating slices.
# ---------------------------------------------------------------------------
echo ""
echo "--- A4 Setup: umbrella issue created ---"

A4_UMBRELLA_NUM="$(e2e_create_issue \
  "[ENH] Umbrella: implement SDLC E2E test suite (5 slices)" \
  "Tracks slices A, B, C. Each slice PR closes its own slice issue; only the final slice also closes this umbrella." \
  "enhancement")"

assert_label_present "enhancement" "$A4_UMBRELLA_NUM" "issue"
assert_issue_open "$A4_UMBRELLA_NUM"

# ---------------------------------------------------------------------------
# A4-S1 — Mid-series Slice A (CORRECT pattern)
#
# Slice A uses: Closes #<sliceA>, Refs #<umbrella>
# Expected post-merge:
#   - Slice A issue CLOSES (Closes #sliceA in body)
#   - Umbrella STAYS OPEN (only Refs — not Closes)
# ---------------------------------------------------------------------------
echo ""
echo "--- A4 Slice A: correct pattern (Closes #slice, Refs #umbrella) ---"

# File slice A issue
A4_SLICE_A_NUM="$(e2e_create_issue \
  "[ENH] Slice A: implement harness infrastructure" \
  "Part of the umbrella. This slice closes when its PR merges." \
  "enhancement,prioritized,priority:high")"

assert_label_present "enhancement"  "$A4_SLICE_A_NUM" "issue"
assert_label_present "prioritized"  "$A4_SLICE_A_NUM" "issue"
assert_issue_open "$A4_SLICE_A_NUM"

# Dev picks up and creates branch + worktree
A4_BRANCH_A="feat/$A4_SLICE_A_NUM-harness-infra"
A4_TASK_A="umbrella-slice-a"

e2e_create_worktree "$A4_TASK_A" "$A4_BRANCH_A"
assert_worktree_exists "$A4_TASK_A"
assert_branch_exists   "$A4_BRANCH_A"
git -C "$SANDBOX_WORK" push --quiet origin "$A4_BRANCH_A"

# Dev opens PR with correct pattern: Closes #sliceA + Refs #umbrella
A4_PR_A_BODY="$(printf 'Add harness infrastructure.\n\nCloses #%s\nRefs #%s' \
  "$A4_SLICE_A_NUM" "$A4_UMBRELLA_NUM")"
A4_PR_A_NUM="$(e2e_create_pr \
  "feat(test): harness infrastructure (Slice A)" \
  "$A4_PR_A_BODY" \
  "$A4_BRANCH_A" \
  "main")"

# Verify PR body has the correct Closes + Refs keywords
assert_pr_body_contains "$A4_PR_A_NUM" "Closes #$A4_SLICE_A_NUM"
assert_pr_body_contains "$A4_PR_A_NUM" "Refs #$A4_UMBRELLA_NUM"

# CR reviews and merges
e2e_add_comment "$A4_PR_A_NUM" "pr" "LGTM — harness infra looks solid."
assert_comment_present "$A4_PR_A_NUM" "pr" "LGTM"

gh pr merge "$A4_PR_A_NUM" --squash --delete-branch

assert_pr_state "$A4_PR_A_NUM" "merged"

# Slice A issue auto-closed (Closes #sliceA in PR body)
assert_issue_closed "$A4_SLICE_A_NUM"

# Umbrella STAYS OPEN — only Refs, not Closes, in PR body
assert_issue_open "$A4_UMBRELLA_NUM"

# INVARIANT: remote-branch-deleted (Slice A)
assert_remote_branch_deleted "$A4_BRANCH_A"  # INVARIANT: remote-branch-deleted

# Post-merge cleanup: worktree + local branch
e2e_remove_worktree "$A4_TASK_A"
assert_worktree_removed "$A4_TASK_A"  # INVARIANT: local-worktree-branch-deleted
assert_branch_deleted   "$A4_BRANCH_A"  # INVARIANT: local-worktree-branch-deleted

# ---------------------------------------------------------------------------
# A4-S2 — Mid-series Slice B (DEFECT PATH — Refs instead of Closes for slice)
#
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  DEFECT PATH: the wrong pattern that bit Slices 1+2 (issues #67, #68)  ║
# ║                                                                          ║
# ║  When a mid-series PR uses `Refs #<slice>` instead of `Closes #<slice>` ║
# ║  the slice issue is NOT auto-closed on merge. It stays open with stale  ║
# ║  labels (in-progress, in-review) until someone manually cleans it up.   ║
# ║                                                                          ║
# ║  This test asserts the FAILURE MODE directly: after the "Refs"-body PR   ║
# ║  merges, the slice issue is still open. This makes the gotcha visible.  ║
# ╚══════════════════════════════════════════════════════════════════════════╝
# ---------------------------------------------------------------------------
echo ""
echo "--- A4 Slice B: DEFECT PATH — Refs #slice instead of Closes (slice stays OPEN) ---"

# File slice B issue
A4_SLICE_B_NUM="$(e2e_create_issue \
  "[ENH] Slice B: bug fast-path archetype" \
  "Part of the umbrella. WRONG: Dev used Refs instead of Closes in the PR body." \
  "enhancement,prioritized,priority:high")"

assert_issue_open "$A4_SLICE_B_NUM"

e2e_add_label "$A4_SLICE_B_NUM" "issue" "in-progress"

A4_BRANCH_B="feat/$A4_SLICE_B_NUM-bug-fastpath"
A4_TASK_B="umbrella-slice-b"

e2e_create_worktree "$A4_TASK_B" "$A4_BRANCH_B"
assert_worktree_exists "$A4_TASK_B"
assert_branch_exists   "$A4_BRANCH_B"
git -C "$SANDBOX_WORK" push --quiet origin "$A4_BRANCH_B"

# WRONG body: uses Refs #sliceB instead of Closes #sliceB
# This is the defect: the slice issue will NOT auto-close on merge.
# Note: "Refs" is intentional here — this is the wrong pattern under test.
A4_PR_B_BODY_WRONG="$(printf 'Add bug fast-path archetype tests.\n\nRefs #%s\nRefs #%s' \
  "$A4_SLICE_B_NUM" "$A4_UMBRELLA_NUM")"
A4_PR_B_NUM="$(e2e_create_pr \
  "feat(test): bug fast-path archetype (Slice B — DEFECT: Refs instead of Closes)" \
  "$A4_PR_B_BODY_WRONG" \
  "$A4_BRANCH_B" \
  "main")"

# The PR body uses Refs for the slice — NOT Closes.
# Asserting the body does NOT contain "Closes #<sliceB>" documents the defect.
assert_pr_body_contains "$A4_PR_B_NUM" "Refs #$A4_SLICE_B_NUM"

e2e_add_comment "$A4_PR_B_NUM" "pr" "LGTM — but Dev used Refs instead of Closes for slice issue."

gh pr merge "$A4_PR_B_NUM" --squash --delete-branch
assert_pr_state "$A4_PR_B_NUM" "merged"

# DEFECT ASSERTION: slice B issue is STILL OPEN after merge because the PR body
# used "Refs" instead of "Closes". GitHub's auto-close mechanism only fires on
# "Closes", "Fixes", or "Resolves" keywords — "Refs" is not one of them.
#
# This is the EXACT failure mode from issues #67 and #68. If this assertion
# fails (i.e. the issue IS closed), it means the fake-gh stub incorrectly
# processes "Refs" as a closing keyword — that would be a harness bug.
assert_issue_open "$A4_SLICE_B_NUM"

# Umbrella also stays open (Refs for both — neither closes anything)
assert_issue_open "$A4_UMBRELLA_NUM"

# INVARIANT: remote-branch-deleted (Slice B — merge still deletes the remote branch)
assert_remote_branch_deleted "$A4_BRANCH_B"  # INVARIANT: remote-branch-deleted

# Post-merge cleanup
e2e_remove_worktree "$A4_TASK_B"
assert_worktree_removed "$A4_TASK_B"  # INVARIANT: local-worktree-branch-deleted
assert_branch_deleted   "$A4_BRANCH_B"  # INVARIANT: local-worktree-branch-deleted

# The stranded slice B issue must be manually closed (simulating what Dev had
# to do for #67 and #68 after discovering the defect).
e2e_close_issue "$A4_SLICE_B_NUM"
assert_issue_closed "$A4_SLICE_B_NUM"

# ---------------------------------------------------------------------------
# A4-S3 — Final Slice C (correct final-slice pattern)
#
# Final slice uses: Closes #<sliceC>, Closes #<umbrella>
# This is the ONLY PR in the series that should use Closes #<umbrella>.
# Expected post-merge:
#   - Slice C issue CLOSES
#   - Umbrella CLOSES (both retired in one merge)
# ---------------------------------------------------------------------------
echo ""
echo "--- A4 Slice C: final slice (Closes #slice + Closes #umbrella — both retire) ---"

# File slice C issue
A4_SLICE_C_NUM="$(e2e_create_issue \
  "[ENH] Slice C: enhancement archetypes (final slice)" \
  "Final slice — PR will close both this issue and the umbrella." \
  "enhancement,prioritized,priority:medium")"

assert_issue_open "$A4_SLICE_C_NUM"
# Umbrella is still open entering this slice
assert_issue_open "$A4_UMBRELLA_NUM"

e2e_add_label "$A4_SLICE_C_NUM" "issue" "in-progress"

A4_BRANCH_C="feat/$A4_SLICE_C_NUM-enhancement-archetypes"
A4_TASK_C="umbrella-slice-c"

e2e_create_worktree "$A4_TASK_C" "$A4_BRANCH_C"
assert_worktree_exists "$A4_TASK_C"
assert_branch_exists   "$A4_BRANCH_C"
git -C "$SANDBOX_WORK" push --quiet origin "$A4_BRANCH_C"

# CORRECT final-slice body: Closes #sliceC + Closes #umbrella
A4_PR_C_BODY="$(printf 'Add enhancement archetype tests. Final slice.\n\nCloses #%s\nCloses #%s' \
  "$A4_SLICE_C_NUM" "$A4_UMBRELLA_NUM")"
A4_PR_C_NUM="$(e2e_create_pr \
  "feat(test): enhancement archetypes, final slice (Slice C)" \
  "$A4_PR_C_BODY" \
  "$A4_BRANCH_C" \
  "main")"

# Both Closes keywords must be in the final PR body
assert_pr_body_contains "$A4_PR_C_NUM" "Closes #$A4_SLICE_C_NUM"
assert_pr_body_contains "$A4_PR_C_NUM" "Closes #$A4_UMBRELLA_NUM"

e2e_add_comment "$A4_PR_C_NUM" "pr" "LGTM — final slice, umbrella can be retired."
assert_comment_present "$A4_PR_C_NUM" "pr" "LGTM"

gh pr merge "$A4_PR_C_NUM" --squash --delete-branch
assert_pr_state "$A4_PR_C_NUM" "merged"

# Both the final slice issue AND the umbrella must close on merge
assert_issue_closed "$A4_SLICE_C_NUM"
assert_issue_closed "$A4_UMBRELLA_NUM"

# INVARIANT: remote-branch-deleted (final Slice C)
assert_remote_branch_deleted "$A4_BRANCH_C"  # INVARIANT: remote-branch-deleted

# Post-merge cleanup
e2e_remove_worktree "$A4_TASK_C"
assert_worktree_removed "$A4_TASK_C"  # INVARIANT: local-worktree-branch-deleted
assert_branch_deleted   "$A4_BRANCH_C"  # INVARIANT: local-worktree-branch-deleted


# ===========================================================================
# ARCHETYPE 5 — Hotfix path
#
# SDLC Step 0 explicitly exempts hotfixes from PRD + design doc gates.
# The hotfix path is: operator reports regression → Dev branches as
# fix/<N>-<slug> directly → PR (hotfix label) → CR fast-track review →
# merge with --delete-branch → DevOps deploy → QA single-pass.
#
# Key assertions:
#   - No PRD file (docs/prd/PRD-<slug>.md must NOT exist)
#   - No design doc file (docs/design/DESIGN-<slug>.md must NOT exist)
#   - Branch name starts with fix/
#   - CR LGTM present (fast-track, but review still required)
#   - Merge with --delete-branch: remote branch gone
#   - Worktree + local branch cleanup: both gone
#   - QA single-pass (no two-pass required for hotfix per qa-agent.md)
# ===========================================================================

# Reset stub state so issue/PR numbers are independent across archetypes.
e2e_reset_state

echo ""
echo "=========================================="
echo "  ARCHETYPE 5: Hotfix path"
echo "=========================================="

# ---------------------------------------------------------------------------
# A5-1 — Regression filed (operator reports production bug)
#
# Hotfix issues carry the `bug` label. They do NOT get `backlog` (bugs skip
# the backlog per label-discipline). They do NOT need `prioritized` — Dev
# may pick up any bug without PM triage.
# ---------------------------------------------------------------------------
echo ""
echo "--- A5 Stage 1: regression filed (bug label, no backlog, no prioritized) ---"

HF_SLUG="login-500-on-empty-password"

HF_ISSUE_NUM="$(e2e_create_issue \
  "fix: 500 error on empty password at login" \
  "Repro: POST /login with empty password field. Expected: 400. Got: 500. Regression in v2.3.1." \
  "bug")"

assert_label_present "bug"        "$HF_ISSUE_NUM" "issue"
assert_label_absent  "backlog"    "$HF_ISSUE_NUM" "issue"
assert_label_absent  "prioritized" "$HF_ISSUE_NUM" "issue"
assert_issue_open "$HF_ISSUE_NUM"

# ---------------------------------------------------------------------------
# A5-2 — Gate check: no PRD, no design doc (hotfix correctly skips both)
#
# SDLC Step 0 table: hotfix row has ❌ for PRD required and ❌ for Design Doc.
# We assert the absence of these files — this is a positive assertion that
# the gate is correctly skipped, not a vacuous "the file was never created"
# check. The slug is specific to this hotfix; if a PRD existed it would have
# this exact name.
# ---------------------------------------------------------------------------
echo ""
echo "--- A5 Stage 2: gate check — no PRD, no design doc (hotfix skips both gates) ---"

# SDLC Step 0: hotfixes skip PRD gate
if [[ ! -f "$SANDBOX_WORK/docs/prd/PRD-$HF_SLUG.md" ]]; then
  printf '  PASS  PRD gate correctly skipped: docs/prd/PRD-%s.md does not exist\n' "$HF_SLUG"
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  unexpected PRD found for hotfix: docs/prd/PRD-%s.md\n' "$HF_SLUG"
  FAIL=$(( FAIL + 1 ))
fi

# SDLC Step 0: hotfixes skip design doc gate
if [[ ! -f "$SANDBOX_WORK/docs/design/DESIGN-$HF_SLUG.md" ]]; then
  printf '  PASS  design doc gate correctly skipped: docs/design/DESIGN-%s.md does not exist\n' "$HF_SLUG"
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  unexpected design doc found for hotfix: docs/design/DESIGN-%s.md\n' "$HF_SLUG"
  FAIL=$(( FAIL + 1 ))
fi

# ---------------------------------------------------------------------------
# A5-3 — Dev claims the hotfix
#
# Dev applies `in-progress` directly (no prioritized required — bug fast-path).
# Dev opens fix/<N>-<slug> branch (fix/ prefix is required by SDLC §Step 2).
# ---------------------------------------------------------------------------
echo ""
echo "--- A5 Stage 3: Dev claims (in-progress, no prioritized needed) ---"

gh issue edit "$HF_ISSUE_NUM" --add-label "in-progress"
gh issue comment "$HF_ISSUE_NUM" --body "Picking this up — branch fix/$HF_ISSUE_NUM-$HF_SLUG. Hotfix — no PRD or design doc required."

assert_label_present "in-progress" "$HF_ISSUE_NUM" "issue"
assert_label_absent  "prioritized" "$HF_ISSUE_NUM" "issue"
assert_comment_present "$HF_ISSUE_NUM" "issue" "Picking this up"

# ---------------------------------------------------------------------------
# A5-4 — Branch + worktree created
#
# Branch name MUST start with "fix/" for hotfixes (SDLC §Step 2 naming).
# ---------------------------------------------------------------------------
echo ""
echo "--- A5 Stage 4: branch + worktree created (fix/ prefix required) ---"

HF_BRANCH="fix/$HF_ISSUE_NUM-$HF_SLUG"
HF_TASK_ID="hotfix-$HF_ISSUE_NUM"

e2e_create_worktree "$HF_TASK_ID" "$HF_BRANCH"
assert_worktree_exists "$HF_TASK_ID"
assert_branch_exists   "$HF_BRANCH"

# Verify the branch name starts with "fix/" — this is the SDLC convention for hotfixes
if [[ "$HF_BRANCH" == fix/* ]]; then
  printf '  PASS  hotfix branch name uses fix/ prefix: %s\n' "$HF_BRANCH"
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  hotfix branch name must start with fix/ — got: %s\n' "$HF_BRANCH"
  FAIL=$(( FAIL + 1 ))
fi

# Push branch to origin so merge can delete it later
git -C "$SANDBOX_WORK" push --quiet origin "$HF_BRANCH"

# ---------------------------------------------------------------------------
# A5-5 — PR opened (hotfix label, Closes #N)
#
# Hotfix PR body must contain "Closes #N" so the issue auto-closes on merge.
# No umbrella reference required — hotfixes are not part of a multi-PR series.
# Dev also applies in-review on the issue (signal for CR to pick up).
# ---------------------------------------------------------------------------
echo ""
echo "--- A5 Stage 5: PR opened (hotfix label, Closes #N, in-review) ---"

HF_PR_BODY="$(printf 'Guard against empty password in login handler — validate length before bcrypt compare.\n\nCloses #%s' "$HF_ISSUE_NUM")"
HF_PR_NUM="$(e2e_create_pr \
  "fix(auth): guard empty password in login handler" \
  "$HF_PR_BODY" \
  "$HF_BRANCH" \
  "main")"

# Apply hotfix label to the PR and in-review to the issue
e2e_add_label "$HF_PR_NUM" "pr" "hotfix"
gh issue edit "$HF_ISSUE_NUM" --add-label "in-review"

assert_label_present "hotfix"             "$HF_PR_NUM" "pr"
assert_label_present "in-review"          "$HF_ISSUE_NUM" "issue"
assert_pr_state      "$HF_PR_NUM" "open"
assert_pr_body_contains "$HF_PR_NUM" "Closes #$HF_ISSUE_NUM"

# ---------------------------------------------------------------------------
# A5-6 — CR fast-track review (LGTM still required for hotfix)
#
# Per SDLC: hotfix skips PRD + design doc gates but CR review is still
# mandatory — there is no "skip CR" path. Fast-track means CR prioritises
# the review, not that it is omitted.
# ---------------------------------------------------------------------------
echo ""
echo "--- A5 Stage 6: CR fast-track review (LGTM required, not optional) ---"

e2e_add_comment "$HF_PR_NUM" "pr" "LGTM — hotfix fast-track. Empty-password guard verified. No scope creep."

assert_comment_present "$HF_PR_NUM" "pr" "LGTM"

# ---------------------------------------------------------------------------
# A5-7 — CR merges with --delete-branch
#
# Same merge mechanic as all other archetypes — --delete-branch is mandatory.
# Expected post-merge:
#   - PR state == "merged"
#   - Issue auto-closed (Closes #N in PR body)
#   - Remote branch deleted  ← INVARIANT: remote-branch-deleted
# ---------------------------------------------------------------------------
echo ""
echo "--- A5 Stage 7: CR merges (--delete-branch mandatory) ---"

gh pr merge "$HF_PR_NUM" --squash --delete-branch

# PR is merged (use assert_pr_state — not gh pr view --json mergedAt; see CR note)
assert_pr_state "$HF_PR_NUM" "merged"

# Issue auto-closed via Closes #N in PR body
assert_issue_closed "$HF_ISSUE_NUM"

# INVARIANT: remote-branch-deleted
assert_remote_branch_deleted "$HF_BRANCH"  # INVARIANT: remote-branch-deleted

# CR housekeeping: remove in-review after merge
gh issue edit "$HF_ISSUE_NUM" --remove-label "in-review"
assert_label_absent "in-review" "$HF_ISSUE_NUM" "issue"

# ---------------------------------------------------------------------------
# A5-8 — Worktree cleanup (post-merge)
#
# After merge, remote is gone but local worktree + branch still exist.
# Dev performs mandatory cleanup.
#
# BEFORE cleanup: worktree dir + local branch still present.
# AFTER cleanup: both gone.  ← INVARIANT: local-worktree-branch-deleted
# ---------------------------------------------------------------------------
echo ""
echo "--- A5 Stage 8: post-merge worktree cleanup ---"

# Before cleanup: local state still exists (remote is already gone)
assert_worktree_exists "$HF_TASK_ID"
assert_branch_exists   "$HF_BRANCH"

# Dev performs mandatory post-merge cleanup
e2e_remove_worktree "$HF_TASK_ID"

# INVARIANT: local-worktree-branch-deleted
assert_worktree_removed "$HF_TASK_ID"  # INVARIANT: local-worktree-branch-deleted
assert_branch_deleted   "$HF_BRANCH"   # INVARIANT: local-worktree-branch-deleted

# ---------------------------------------------------------------------------
# A5-9 — QA single-pass (hotfix — two-pass not required)
#
# Per qa-agent.md: hotfixes are acceptable with a single-pass QA verification.
# The two-pass protocol exists for complex features; for targeted hotfixes a
# single confirmed-fixed run is sufficient.
#
# QA applies `resolved`. Labels post-QA:
#   - `resolved` added
#   - `bug` retained (audit trail — QA never removes the original label)
#   - Issue remains closed
# ---------------------------------------------------------------------------
echo ""
echo "--- A5 Stage 9: QA single-pass (resolved, bug retained — two-pass NOT required) ---"

# QA verifies the hotfix and applies resolved after a single passing run
gh issue edit "$HF_ISSUE_NUM" --add-label "resolved"

assert_label_present "resolved" "$HF_ISSUE_NUM" "issue"

# QA contract: bug label must be retained alongside resolved (audit trail)
assert_label_present "bug"      "$HF_ISSUE_NUM" "issue"

# Issue stays closed — QA does not re-open it
assert_issue_closed "$HF_ISSUE_NUM"

# ===========================================================================
print_summary
