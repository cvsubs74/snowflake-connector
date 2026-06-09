#!/usr/bin/env bash
# tests/test_e2e_bug_fastpath.sh — Bug fast-path archetype (Slice 2, Issue #68).
#
# Exercises the complete bug fast-path lifecycle through the fake-gh stub,
# with assertions at every state transition defined in the SDLC:
#
#   Triage/Operator/QA files bug
#     → Dev claims (in-progress, no prioritized required)
#     → Dev branch + worktree created
#     → PR opened (in-review, Closes #N)
#     → CR posts LGTM comment
#     → CR merges with --delete-branch
#         ⟶ PR merged, issue auto-closed, REMOTE BRANCH DELETED
#     → Dev cleans up worktree post-merge
#         ⟶ LOCAL WORKTREE REMOVED, LOCAL BRANCH DELETED
#     → QA two-pass: resolved applied, bug label retained
#
# The two bolded invariants (remote branch deleted + local worktree/branch
# deleted) are the operator's explicit requirement for this slice. They are
# asserted at lines tagged with "# INVARIANT: remote-branch-deleted" and
# "# INVARIANT: local-worktree-branch-deleted" — grep-able for code review.
#
# Harness prerequisites:
#   tests/lib.sh       — PASS/FAIL counters + print_summary (Slice 0)
#   tests/lib_e2e.sh   — sandbox + helpers (Slice 1, SHA 5a90840)
#
# CR note (carried forward from Slice 1 review of PR #73):
#   Use assert_pr_state <num> "merged" — NOT gh pr view --json mergedAt.
#   The stub stores merge time as merged_at (snake) but the --json mergedAt
#   camelCase selector does not surface it.

# shellcheck source=./lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=./lib_e2e.sh
source "$(dirname "$0")/lib_e2e.sh"

e2e_setup

# ===========================================================================
# STAGE 1 — Bug filed
#
# Triage/Operator/QA files the bug. The issue must have the `bug` label and
# must NOT have `backlog` (bugs skip the backlog per label-discipline).
# ===========================================================================
echo "--- Stage 1: bug filed ---"

BUG_ISSUE_NUM="$(e2e_create_issue \
  "fix: null pointer in auth handler" \
  "Repro: hit /api/auth with a missing token. Expected: 401. Got: 500." \
  "bug")"

assert_label_present "bug"     "$BUG_ISSUE_NUM" "issue"
assert_label_absent  "backlog" "$BUG_ISSUE_NUM" "issue"
assert_issue_open "$BUG_ISSUE_NUM"

# ===========================================================================
# STAGE 2 — Dev claims the issue
#
# Dev applies in-progress (no `prioritized` required — bugs are fast-path).
# ===========================================================================
echo ""
echo "--- Stage 2: Dev claims issue ---"

gh issue edit "$BUG_ISSUE_NUM" --add-label "in-progress"
gh issue comment "$BUG_ISSUE_NUM" --body "Picking this up — branch fix/$BUG_ISSUE_NUM-auth-null-ptr."

assert_label_present "in-progress" "$BUG_ISSUE_NUM" "issue"
assert_label_absent  "prioritized" "$BUG_ISSUE_NUM" "issue"
assert_comment_present "$BUG_ISSUE_NUM" "issue" "Picking this up"

# ===========================================================================
# STAGE 3 — Branch + worktree created
#
# Dev creates a feature branch and a git worktree. Both must exist.
# ===========================================================================
echo ""
echo "--- Stage 3: branch + worktree created ---"

BUG_BRANCH="fix/$BUG_ISSUE_NUM-auth-null-ptr"
BUG_TASK_ID="bug-$BUG_ISSUE_NUM"

e2e_create_worktree "$BUG_TASK_ID" "$BUG_BRANCH"

assert_worktree_exists "$BUG_TASK_ID"
assert_branch_exists   "$BUG_BRANCH"

# Push the branch to origin so merge can delete it later
git -C "$SANDBOX_WORK" push --quiet origin "$BUG_BRANCH"

# ===========================================================================
# STAGE 4 — PR opened
#
# Dev opens a PR, applies in-review on the issue, and ensures the PR body
# contains "Closes #<bug>" so GitHub auto-closes on merge.
# ===========================================================================
echo ""
echo "--- Stage 4: PR opened ---"

PR_BODY="$(printf 'Guard against nil token in auth handler.\n\nCloses #%s' "$BUG_ISSUE_NUM")"
BUG_PR_NUM="$(e2e_create_pr \
  "fix(auth): guard nil token in auth handler" \
  "$PR_BODY" \
  "$BUG_BRANCH" \
  "main")"

# Apply in-review on the issue (Dev's signal that PR is open and awaiting CR)
gh issue edit "$BUG_ISSUE_NUM" --add-label "in-review"

assert_label_present "in-review" "$BUG_ISSUE_NUM" "issue"
assert_pr_state      "$BUG_PR_NUM" "open"
assert_pr_body_contains "$BUG_PR_NUM" "Closes #$BUG_ISSUE_NUM"

# ===========================================================================
# STAGE 5 — CR posts LGTM
#
# Code Reviewer reviews the diff and posts a top-level LGTM comment on the PR.
# The comment prefix "LGTM" is the SDLC contract.
# ===========================================================================
echo ""
echo "--- Stage 5: CR posts LGTM ---"

e2e_add_comment "$BUG_PR_NUM" "pr" "LGTM — null-check added, regression test covers the 500 path."

assert_comment_present "$BUG_PR_NUM" "pr" "LGTM"

# ===========================================================================
# STAGE 6 — CR merges with --delete-branch
#
# CR runs: gh pr merge <N> --squash --delete-branch
# Expect:
#   - PR state == "merged"
#   - Issue auto-closed (Closes #N in body)
#   - Remote branch deleted  ← INVARIANT: remote-branch-deleted
#   - in-review label removed from issue (CR housekeeping, post-merge)
# ===========================================================================
echo ""
echo "--- Stage 6: CR merges (--delete-branch) ---"

gh pr merge "$BUG_PR_NUM" --squash --delete-branch

# PR is merged (use assert_pr_state — not gh pr view --json mergedAt; see CR note above)
assert_pr_state "$BUG_PR_NUM" "merged"

# Issue auto-closed via Closes #N in PR body
assert_issue_closed "$BUG_ISSUE_NUM"

# INVARIANT: remote-branch-deleted
# Remote branch must be gone immediately after merge with --delete-branch.
assert_remote_branch_deleted "$BUG_BRANCH"  # INVARIANT: remote-branch-deleted

# CR removes in-review once the PR merges
gh issue edit "$BUG_ISSUE_NUM" --remove-label "in-review"
assert_label_absent "in-review" "$BUG_ISSUE_NUM" "issue"

# ===========================================================================
# STAGE 7 — Worktree cleanup (post-merge)
#
# After the PR merges, the local worktree dir and local branch still exist
# (the remote is gone but local state is untouched until Dev explicitly
# cleans up). Dev runs:
#   git worktree remove .worktrees/<task-id>
#   git branch -D <branch>
#
# Expect BEFORE cleanup:
#   - worktree dir still present
#   - local branch still present
#
# Expect AFTER cleanup:
#   - worktree dir removed  ← INVARIANT: local-worktree-branch-deleted
#   - local branch deleted  ← INVARIANT: local-worktree-branch-deleted
# ===========================================================================
echo ""
echo "--- Stage 7: post-merge worktree cleanup ---"

# Before cleanup: local worktree and branch still exist (remote is already gone)
assert_worktree_exists "$BUG_TASK_ID"
assert_branch_exists   "$BUG_BRANCH"

# Dev performs mandatory post-merge cleanup
e2e_remove_worktree "$BUG_TASK_ID"

# INVARIANT: local-worktree-branch-deleted
# Both the worktree directory and the local branch must be gone.
assert_worktree_removed "$BUG_TASK_ID"  # INVARIANT: local-worktree-branch-deleted
assert_branch_deleted   "$BUG_BRANCH"   # INVARIANT: local-worktree-branch-deleted

# ===========================================================================
# STAGE 8 — QA two-pass verification
#
# QA runs the original repro twice post-merge and, on two consecutive passes,
# applies the `resolved` label. Per the QA contract (qa-agent.md §TWO-PASS):
#   - `resolved` is added
#   - `bug` label is retained (QA never removes it — it is audit trail)
#   - Issue remains closed (already auto-closed at Stage 6)
# ===========================================================================
echo ""
echo "--- Stage 8: QA two-pass (resolved applied, bug retained) ---"

# QA applies resolved after two consecutive passing runs
gh issue edit "$BUG_ISSUE_NUM" --add-label "resolved"

assert_label_present "resolved" "$BUG_ISSUE_NUM" "issue"

# QA contract: bug label must be retained alongside resolved
assert_label_present "bug"      "$BUG_ISSUE_NUM" "issue"

# Issue stays closed — QA does not re-open it
assert_issue_closed "$BUG_ISSUE_NUM"

# ===========================================================================
print_summary
