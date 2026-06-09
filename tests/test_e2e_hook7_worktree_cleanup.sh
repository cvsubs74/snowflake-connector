#!/usr/bin/env bash
# tests/test_e2e_hook7_worktree_cleanup.sh — E2E test for Hook 7 (Issue #72).
#
# Validates Hook 7 (auto-clean-worktree.sh) against the same operator invariant
# that Slices 2–5 assert manually: after a PR merge the local worktree and local
# branch must be gone.
#
# Scope: Hook 7 is a PostToolUse/Bash hook, so it fires after the Bash tool
# returns in Claude Code — not during a `gh pr merge` call inside the E2E sandbox.
# This test drives Hook 7 directly with a synthetic PostToolUse payload, then
# asserts the worktree and branch state that it should have produced.
#
# Scenarios tested:
#   1. Hook 7 fires after merge: worktree removed, branch deleted.          (INVARIANT)
#   2. Hook 7 is silent when no matching worktree exists (Dev cleaned up).
#   3. Hook 7 warns and skips a dirty worktree.
#   4. Hook 7 ignores a non-.worktrees/ worktree (scope guard).
#
# INVARIANT tags (grep-able for code review):
#   "# INVARIANT: hook7-worktree-cleanup" — the core operator invariant
#
# Harness prerequisites:
#   tests/lib.sh       — PASS/FAIL counters + print_summary
#   tests/lib_e2e.sh   — sandbox + helpers

# shellcheck source=./lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=./lib_e2e.sh
source "$(dirname "$0")/lib_e2e.sh"

e2e_setup

HOOK="$HOOKS_DIR/auto-clean-worktree.sh"

# ---------------------------------------------------------------------------
# Helper: invoke Hook 7 with a PostToolUse payload and capture stderr.
# Returns the hook's exit code (always 0) via $?.
# Caller inspects $HOOK7_STDERR.
# ---------------------------------------------------------------------------
HOOK7_STDERR=""
invoke_hook7() {
  local cmd="$1"
  local tool_out="${2:-}"
  local tool_err="${3:-}"
  local gh_branch_cmd="$4"
  local repo_root="$5"

  local payload
  # Use real runtime field names (issue #81 fix): stdout/stderr/exit_code
  payload="$(jq -cn \
    --arg cmd "$cmd" \
    --arg out "$tool_out" \
    --arg err "$tool_err" \
    '{"tool_name":"Bash","tool_input":{"command":$cmd},"tool_response":{"stdout":$out,"stderr":$err,"exit_code":0}}')"

  # Use `env` to pass env vars to the entire pipeline rather than inline assignment
  # (inline assignment only applies to the first command, not the piped bash process).
  local payload_file
  payload_file="$(mktemp)"
  printf '%s' "$payload" > "$payload_file"
  HOOK7_STDERR="$(env \
    CLAUDE_HOOK_TEST_GH_BRANCH_CMD="$gh_branch_cmd" \
    CLAUDE_HOOK_TEST_REPO_ROOT="$repo_root" \
    bash "$HOOK" < "$payload_file" 2>&1 >/dev/null || true)"
  rm -f "$payload_file"
}

# ---------------------------------------------------------------------------
# SCENARIO 1 — Full cleanup path: merge fires, Hook 7 removes worktree+branch.
#
# Setup:
#   - Create feature branch and worktree in the sandbox.
#   - Build a gh-branch stub that echoes the feature branch name.
#   - Call invoke_hook7 with a successful merge payload.
#
# Expect:
#   - Worktree directory gone.                  INVARIANT: hook7-worktree-cleanup
#   - Local branch deleted.                     INVARIANT: hook7-worktree-cleanup
#   - Hook logs "Removing worktree" to stderr.
# ---------------------------------------------------------------------------
echo "--- Scenario 1: Hook 7 fires, worktree + branch cleaned up ---"

H7_BRANCH="feat/72-hook7-e2e-test"
H7_TASK_ID="hook7-e2e"

e2e_create_worktree "$H7_TASK_ID" "$H7_BRANCH"
git -C "$SANDBOX_WORK" push --quiet origin "$H7_BRANCH"

assert_worktree_exists "$H7_TASK_ID"
assert_branch_exists   "$H7_BRANCH"

# Build branch stub
H7_STUB="$SANDBOX_ROOT/hook7_branch_stub.sh"
printf '#!/usr/bin/env bash\necho "%s"\n' "$H7_BRANCH" > "$H7_STUB"
chmod +x "$H7_STUB"

# Simulate a successful gh pr merge (empty output, empty error = success)
invoke_hook7 \
  "gh pr merge 1 --squash --delete-branch" \
  "" "" \
  "$H7_STUB" "$SANDBOX_WORK"

# INVARIANT: hook7-worktree-cleanup — worktree directory removed
assert_worktree_removed "$H7_TASK_ID"  # INVARIANT: hook7-worktree-cleanup

# INVARIANT: hook7-worktree-cleanup — local branch deleted
assert_branch_deleted "$H7_BRANCH"  # INVARIANT: hook7-worktree-cleanup

# Hook logged "Removing worktree" to stderr
if printf '%s' "$HOOK7_STDERR" | grep -q "\[auto-clean-worktree\] Removing"; then
  printf '  PASS  Hook 7 logged cleanup action to stderr\n'
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  Hook 7 did not log cleanup action (stderr: %s)\n' "$HOOK7_STDERR"
  FAIL=$(( FAIL + 1 ))
fi

# ---------------------------------------------------------------------------
# SCENARIO 2 — No matching worktree (Dev already cleaned up manually).
#
# Dev removed the worktree before Hook 7 ran — this is valid state.
# Hook 7 must stay silent (no WARNING, no error output).
# ---------------------------------------------------------------------------
echo ""
echo "--- Scenario 2: No matching worktree — Hook 7 silent ---"

# Worktree already gone from Scenario 1 — nothing to recreate.
invoke_hook7 \
  "gh pr merge 2 --squash --delete-branch" \
  "" "" \
  "$H7_STUB" "$SANDBOX_WORK"

if [[ -z "$HOOK7_STDERR" ]]; then
  printf '  PASS  Hook 7 silent when no matching worktree\n'
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  Hook 7 produced unexpected output (stderr: %s)\n' "$HOOK7_STDERR"
  FAIL=$(( FAIL + 1 ))
fi

# ---------------------------------------------------------------------------
# SCENARIO 3 — Dirty worktree (uncommitted changes).
#
# Hook 7 must NOT remove a worktree with uncommitted changes.
# It must log a WARNING and leave the worktree intact.
# ---------------------------------------------------------------------------
echo ""
echo "--- Scenario 3: Dirty worktree — Hook 7 warns, skips ---"

H7_DIRTY_BRANCH="feat/72-hook7-e2e-dirty"
H7_DIRTY_TASK="hook7-e2e-dirty"

e2e_create_worktree "$H7_DIRTY_TASK" "$H7_DIRTY_BRANCH"
git -C "$SANDBOX_WORK" push --quiet origin "$H7_DIRTY_BRANCH"

# Plant an uncommitted file to make the worktree dirty
printf 'uncommitted work\n' > "$SANDBOX_WORK/.worktrees/$H7_DIRTY_TASK/wip.txt"

# Stub that echoes H7_DIRTY_BRANCH
H7_DIRTY_STUB="$SANDBOX_ROOT/hook7_dirty_stub.sh"
printf '#!/usr/bin/env bash\necho "%s"\n' "$H7_DIRTY_BRANCH" > "$H7_DIRTY_STUB"
chmod +x "$H7_DIRTY_STUB"

invoke_hook7 \
  "gh pr merge 3 --squash --delete-branch" \
  "" "" \
  "$H7_DIRTY_STUB" "$SANDBOX_WORK"

# Worktree must still exist (hook refused to remove dirty worktree)
assert_worktree_exists "$H7_DIRTY_TASK"

# Hook must have logged a WARNING
if printf '%s' "$HOOK7_STDERR" | grep -q "\[auto-clean-worktree\] WARNING"; then
  printf '  PASS  Hook 7 warned about dirty worktree\n'
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  Hook 7 did not warn about dirty worktree (stderr: %s)\n' "$HOOK7_STDERR"
  FAIL=$(( FAIL + 1 ))
fi

# Clean up the dirty worktree manually so teardown is clean
rm -f "$SANDBOX_WORK/.worktrees/$H7_DIRTY_TASK/wip.txt"
git -C "$SANDBOX_WORK" worktree remove ".worktrees/$H7_DIRTY_TASK" --force 2>/dev/null || true
git -C "$SANDBOX_WORK" worktree prune 2>/dev/null || true
git -C "$SANDBOX_WORK" branch -D "$H7_DIRTY_BRANCH" 2>/dev/null || true

# ---------------------------------------------------------------------------
# SCENARIO 4 — Scope guard: worktree outside .worktrees/ is left alone.
#
# Hook 7 must only touch worktrees under <repo-root>/.worktrees/. Any worktree
# in another location is outside Hook 7's scope and must be ignored.
# ---------------------------------------------------------------------------
echo ""
echo "--- Scenario 4: Out-of-scope worktree — Hook 7 leaves it alone ---"

H7_OOS_BRANCH="feat/72-hook7-e2e-oos"
H7_OOS_DIR="$SANDBOX_ROOT/oos-worktree"

# Create a branch and a worktree in a directory outside .worktrees/
git -C "$SANDBOX_WORK" branch "$H7_OOS_BRANCH"
git -C "$SANDBOX_WORK" worktree add "$H7_OOS_DIR" "$H7_OOS_BRANCH" --quiet 2>/dev/null

# Stub that echoes H7_OOS_BRANCH
H7_OOS_STUB="$SANDBOX_ROOT/hook7_oos_stub.sh"
printf '#!/usr/bin/env bash\necho "%s"\n' "$H7_OOS_BRANCH" > "$H7_OOS_STUB"
chmod +x "$H7_OOS_STUB"

invoke_hook7 \
  "gh pr merge 4 --squash --delete-branch" \
  "" "" \
  "$H7_OOS_STUB" "$SANDBOX_WORK"

# Out-of-scope worktree must still exist
if [[ -d "$H7_OOS_DIR" ]]; then
  printf '  PASS  Out-of-scope worktree untouched\n'
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  Hook 7 removed an out-of-scope worktree\n'
  FAIL=$(( FAIL + 1 ))
fi

# Hook must have been silent (no cleanup, no warning)
if [[ -z "$HOOK7_STDERR" ]]; then
  printf '  PASS  Hook 7 silent for out-of-scope worktree\n'
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  Hook 7 produced unexpected output for OOS worktree (stderr: %s)\n' "$HOOK7_STDERR"
  FAIL=$(( FAIL + 1 ))
fi

# Clean up the out-of-scope worktree manually
git -C "$SANDBOX_WORK" worktree remove "$H7_OOS_DIR" --force 2>/dev/null || true
git -C "$SANDBOX_WORK" worktree prune 2>/dev/null || true
git -C "$SANDBOX_WORK" branch -D "$H7_OOS_BRANCH" 2>/dev/null || true

# ---------------------------------------------------------------------------
# SCENARIO 5 — bin/merge-pr.sh cleans up worktree in agent-context simulation.
#
# Issue #81 primary fix: since PostToolUse hooks don't fire in agent sub-sessions,
# CR agents must call bin/merge-pr.sh instead of bare `gh pr merge`.
# This scenario validates that bin/merge-pr.sh:
#   (a) merges the PR (via stub)
#   (b) removes the worktree    INVARIANT: hook7-worktree-cleanup
#   (c) deletes the local branch INVARIANT: hook7-worktree-cleanup
#
# Also validates hypothesis #2 fix: merge-pr.sh continues cleanup even when
# gh pr merge exits 1 due to local-branch checkout conflict.
# ---------------------------------------------------------------------------
echo ""
echo "--- Scenario 5: bin/merge-pr.sh — agent-context cleanup path ---"

MERGE_PR_BIN="$_REPO_ROOT/bin/merge-pr.sh"

H7_S5_BRANCH="feat/81-merge-pr-agent-context"
H7_S5_TASK="hook7-e2e-s5"

e2e_create_worktree "$H7_S5_TASK" "$H7_S5_BRANCH"
git -C "$SANDBOX_WORK" push --quiet origin "$H7_S5_BRANCH"

assert_worktree_exists "$H7_S5_TASK"
assert_branch_exists   "$H7_S5_BRANCH"

# Stub merge command: prints "Merged pull request" (merge succeeded) but also
# prints a local-branch conflict line and exits 1 — simulating the gh pr merge
# exit-code-1 edge case from Hypothesis 2 of issue #81.
H7_S5_MERGE_STUB="$SANDBOX_ROOT/merge_stub_s5.sh"
cat > "$H7_S5_MERGE_STUB" <<STUB
#!/usr/bin/env bash
printf 'Merged pull request #1 from %s into main\n' "$H7_S5_BRANCH"
printf 'error: Cannot delete branch '"'"'%s'"'"' checked out at '"'"'/tmp/some-worktree'"'"'\n' "$H7_S5_BRANCH" >&2
exit 1
STUB
chmod +x "$H7_S5_MERGE_STUB"

# Stub branch lookup: returns H7_S5_BRANCH for any PR number
H7_S5_STUB="$SANDBOX_ROOT/hook7_branch_stub_s5.sh"
printf '#!/usr/bin/env bash\necho "%s"\n' "$H7_S5_BRANCH" > "$H7_S5_STUB"
chmod +x "$H7_S5_STUB"

MERGE_PR_STDERR="$(env \
  CLAUDE_HOOK_TEST_REPO_ROOT="$SANDBOX_WORK" \
  CLAUDE_HOOK_TEST_GH_BRANCH_CMD="$H7_S5_STUB" \
  CLAUDE_HOOK_TEST_MERGE_CMD="$H7_S5_MERGE_STUB" \
  bash "$MERGE_PR_BIN" 1 --squash 2>&1 >/dev/null || true)"

# INVARIANT: hook7-worktree-cleanup — worktree directory removed
assert_worktree_removed "$H7_S5_TASK"  # INVARIANT: hook7-worktree-cleanup

# INVARIANT: hook7-worktree-cleanup — local branch deleted
assert_branch_deleted "$H7_S5_BRANCH"  # INVARIANT: hook7-worktree-cleanup

# merge-pr.sh must have logged cleanup action
if printf '%s' "$MERGE_PR_STDERR" | grep -q "\[merge-pr\] Removing worktree"; then
  printf '  PASS  bin/merge-pr.sh logged cleanup action (even with exit-code-1 merge stub)\n'
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  bin/merge-pr.sh did not log cleanup action (stderr: %s)\n' "$MERGE_PR_STDERR"
  FAIL=$(( FAIL + 1 ))
fi

# ===========================================================================
print_summary
