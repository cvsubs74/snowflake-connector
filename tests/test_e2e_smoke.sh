#!/usr/bin/env bash
# tests/test_e2e_smoke.sh — E2E harness smoke test.
#
# Verifies that the harness infrastructure (lib_e2e.sh + fake-gh.sh) works
# end-to-end before any archetype tests are built on top of it.
#
# Covers:
#   - Sandbox creation and cleanup (no leaks)
#   - Fake gh is active (PATH shadowing)
#   - gh issue create / view / edit / close
#   - gh issue list with label/state filters
#   - gh pr create / view / edit / merge
#   - Closes #N auto-close on merge
#   - Remote branch deleted after merge
#   - Local branch deleted after merge
#   - Worktree create / assertion / remove / assertion
#   - All assertion helpers: assert_label_present, assert_label_absent,
#     assert_issue_open, assert_issue_closed, assert_pr_state,
#     assert_worktree_exists, assert_worktree_removed,
#     assert_branch_exists, assert_branch_deleted,
#     assert_remote_branch_deleted, assert_pr_body_contains,
#     assert_comment_present

# shellcheck source=./lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=./lib_e2e.sh
source "$(dirname "$0")/lib_e2e.sh"

e2e_setup

echo "--- E2E smoke: harness setup ---"

# ---------------------------------------------------------------------------
# Stub sentinel: verify fake gh is on PATH (not real gh)
# ---------------------------------------------------------------------------
SENTINEL="$(gh --version 2>&1 | head -1)"
assert_eq "fake gh is active (sentinel check)" "$SENTINEL" "# fake-gh.sh"

# ---------------------------------------------------------------------------
# Issue lifecycle: create → label add → label remove → view → close
# ---------------------------------------------------------------------------
echo ""
echo "--- E2E smoke: issue lifecycle ---"

ISSUE_NUM="$(e2e_create_issue "Fix: sandbox smoke test bug" "Repro: run tests. Expected: pass." "bug")"
assert_eq "issue create returns a number" "$ISSUE_NUM" "1"

assert_issue_open "$ISSUE_NUM"
assert_label_present "bug" "$ISSUE_NUM" "issue"
assert_label_absent "in-progress" "$ISSUE_NUM" "issue"

# Add label via lib_e2e helper
e2e_add_label "$ISSUE_NUM" "issue" "in-progress"
assert_label_present "in-progress" "$ISSUE_NUM" "issue"

# Add label via stub directly (exercises gh issue edit --add-label path)
gh issue edit "$ISSUE_NUM" --add-label "in-review"
assert_label_present "in-review" "$ISSUE_NUM" "issue"

# Remove label
e2e_remove_label "$ISSUE_NUM" "issue" "in-review"
assert_label_absent "in-review" "$ISSUE_NUM" "issue"

# gh issue view --json state
VIEW_STATE="$(gh issue view "$ISSUE_NUM" --json state --jq '.state')"
assert_eq "gh issue view --json state returns open" "$VIEW_STATE" "open"

# gh issue view --json labels --jq extracts label names
VIEW_LABELS="$(gh issue view "$ISSUE_NUM" --json labels --jq '[.labels[].name] | sort | join(",")')"
assert_eq "gh issue view --json labels round-trip" "$VIEW_LABELS" "bug,in-progress"

# Issue comment
e2e_add_comment "$ISSUE_NUM" "issue" "Picking this up — branch feat/smoke-test."
assert_comment_present "$ISSUE_NUM" "issue" "Picking this up"

# ---------------------------------------------------------------------------
# Issue list
# ---------------------------------------------------------------------------
echo ""
echo "--- E2E smoke: issue list ---"

ISSUE_NUM2="$(e2e_create_issue "Second issue" "" "enhancement,backlog")"
assert_eq "second issue gets number 2" "$ISSUE_NUM2" "2"

LIST_COUNT="$(gh issue list --state open --json number --jq 'length')"
assert_eq "issue list returns 2 open issues" "$LIST_COUNT" "2"

LIST_LABEL_COUNT="$(gh issue list --label bug --state open --json number --jq 'length')"
assert_eq "issue list filtered by label=bug returns 1" "$LIST_LABEL_COUNT" "1"

# Close issue 2 directly and test state filter
e2e_close_issue "$ISSUE_NUM2"
LIST_OPEN="$(gh issue list --state open --json number --jq 'length')"
assert_eq "after closing issue 2, only 1 open remains" "$LIST_OPEN" "1"

# ---------------------------------------------------------------------------
# Worktree lifecycle
# ---------------------------------------------------------------------------
echo ""
echo "--- E2E smoke: worktree lifecycle ---"

BRANCH_NAME="feat/smoke-test-branch"
TASK_ID="smoke-1"

# Branch must not exist yet
assert_branch_deleted "$BRANCH_NAME"
assert_worktree_removed "$TASK_ID"

# Create worktree
e2e_create_worktree "$TASK_ID" "$BRANCH_NAME"
assert_worktree_exists "$TASK_ID"
assert_branch_exists "$BRANCH_NAME"

# Push the branch to origin so merge can delete it
git -C "$SANDBOX_WORK" push --quiet origin "$BRANCH_NAME"

# ---------------------------------------------------------------------------
# PR lifecycle: create → label add → merge (with Closes #N auto-close)
# ---------------------------------------------------------------------------
echo ""
echo "--- E2E smoke: PR lifecycle ---"

PR_BODY="$(printf 'Fix the thing.\n\nCloses #%s' "$ISSUE_NUM")"
PR_NUM="$(e2e_create_pr "fix: smoke test" "$PR_BODY" "$BRANCH_NAME" "main")"
assert_eq "pr create returns number 1" "$PR_NUM" "1"

assert_pr_state "$PR_NUM" "open"
assert_pr_body_contains "$PR_NUM" "Closes #$ISSUE_NUM"

# Add in-review label to PR
e2e_add_label "$PR_NUM" "pr" "in-review"
assert_label_present "in-review" "$PR_NUM" "pr"

# Verify gh pr view --json labels works (this is what Hook 3 uses via CLAUDE_HOOK_GH_LABELS_CMD).
# Use compact jq output for comparison — multi-line pretty print vs compact are logically equal.
PR_LABELS="$(gh pr view "$PR_NUM" --json labels --jq '[.labels[].name]' | jq -c .)"
assert_eq "gh pr view --json labels returns in-review" "$PR_LABELS" '["in-review"]'

# Add a comment to the PR
e2e_add_comment "$PR_NUM" "pr" "LGTM — all checks pass."
assert_comment_present "$PR_NUM" "pr" "LGTM"

# Merge the PR
e2e_merge_pr "$PR_NUM"

assert_pr_state "$PR_NUM" "merged"

# Closes #N: issue 1 should now be closed
assert_issue_closed "$ISSUE_NUM"

# Remote branch is gone (stub deletes it on merge)
assert_remote_branch_deleted "$BRANCH_NAME"

# ---------------------------------------------------------------------------
# Worktree cleanup
# ---------------------------------------------------------------------------
echo ""
echo "--- E2E smoke: worktree removal ---"

# After merge, the remote branch is gone but the worktree and local branch
# still exist — this is the invariant the operator cares about (and why
# Archetype 1 in Slice 2 makes it a first-class assertion).
# Manually perform the post-merge cleanup that Dev agents are required to do.
assert_worktree_exists "$TASK_ID"

e2e_remove_worktree "$TASK_ID"
assert_worktree_removed "$TASK_ID"

# Local branch deleted as part of worktree removal
assert_branch_deleted "$BRANCH_NAME"

# ---------------------------------------------------------------------------
# gh pr list
# ---------------------------------------------------------------------------
echo ""
echo "--- E2E smoke: PR list ---"

PR_LIST_COUNT="$(gh pr list --state merged --json number --jq 'length')"
assert_eq "pr list --state merged returns 1" "$PR_LIST_COUNT" "1"

OPEN_PR_COUNT="$(gh pr list --state open --json number --jq 'length')"
assert_eq "pr list --state open returns 0" "$OPEN_PR_COUNT" "0"

# ---------------------------------------------------------------------------
# Sandbox teardown verification
# (trap handles the actual rm -rf; we check SANDBOX_ROOT is set)
# ---------------------------------------------------------------------------
echo ""
echo "--- E2E smoke: teardown ---"

assert_eq "SANDBOX_ROOT is set" "$(test -n "$SANDBOX_ROOT" && echo yes || echo no)" "yes"

# The trap will fire on EXIT and delete $SANDBOX_ROOT. We can't assert the dir
# is gone here (we're still inside the process). The absence of leaked
# /tmp/tmp.* directories after the full test run is validated by CI.

print_summary
