#!/usr/bin/env bash
# tests/lib_e2e.sh — E2E test harness library.
#
# Provides sandbox lifecycle management, a fake `gh` stub wired via PATH, and
# assertion helpers for label state, worktree existence, branch existence, PR
# state, and issue state.
#
# Usage (in a test_e2e_*.sh file):
#
#   source "$(dirname "$0")/lib.sh"       # for PASS/FAIL counters + print_summary
#   source "$(dirname "$0")/lib_e2e.sh"   # for harness + assertion helpers
#
#   e2e_setup      # once per test file; registers EXIT trap for teardown
#   ...            # test scenarios using helpers below
#   print_summary  # from lib.sh — exits non-zero on any FAIL
#
# Design doc: docs/design/DESIGN-sdlc-e2e-test-suite.md

# Note: do NOT `set -e` here — callers are test files that must keep going.
set -uo pipefail

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
_LIB_E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="$(cd "$_LIB_E2E_DIR/.." && pwd)"
_FAKE_GH="$_LIB_E2E_DIR/fixtures/fake-gh.sh"

# ---------------------------------------------------------------------------
# Sandbox state (populated by e2e_setup)
# ---------------------------------------------------------------------------
SANDBOX_ROOT=""      # mktemp -d — destroyed on EXIT
SANDBOX_REPO=""      # $SANDBOX_ROOT/repo — bare git repo acting as origin
SANDBOX_WORK=""      # $SANDBOX_ROOT/work — working clone
GH_STATE_FILE=""     # $SANDBOX_ROOT/gh-state.json — fake gh state

# ---------------------------------------------------------------------------
# e2e_setup
#
# Creates the sandbox, initialises git repos, wires the fake gh stub into PATH,
# and registers the EXIT trap. Must be called once per test file before any
# other helper.
# ---------------------------------------------------------------------------
e2e_setup() {
  SANDBOX_ROOT="$(mktemp -d)"
  SANDBOX_REPO="$SANDBOX_ROOT/repo"
  SANDBOX_WORK="$SANDBOX_ROOT/work"
  GH_STATE_FILE="$SANDBOX_ROOT/gh-state.json"

  export SANDBOX_ROOT SANDBOX_REPO SANDBOX_WORK GH_STATE_FILE

  # Register teardown trap — fires on EXIT, INT, TERM, so cleanup always runs.
  trap 'e2e_teardown' EXIT INT TERM

  # Create bare "remote" repo
  git init --bare "$SANDBOX_REPO" --quiet
  git -C "$SANDBOX_REPO" config receive.denyCurrentBranch ignore

  # Create working clone off the bare repo
  git clone --quiet "$SANDBOX_REPO" "$SANDBOX_WORK" 2>/dev/null

  # Give the clone a usable identity so commits work in CI without global config
  git -C "$SANDBOX_WORK" config user.email "test@example.com"
  git -C "$SANDBOX_WORK" config user.name "E2E Test"

  # Create an initial commit so the branch exists and we can push
  git -C "$SANDBOX_WORK" commit --quiet --allow-empty -m "chore: initial sandbox commit"
  git -C "$SANDBOX_WORK" push --quiet origin HEAD:main

  # Make sure origin/main tracking is set
  git -C "$SANDBOX_WORK" branch --set-upstream-to=origin/main main 2>/dev/null || true

  # Create .worktrees directory inside work (mirrors real project layout)
  mkdir -p "$SANDBOX_WORK/.worktrees"

  # Wire fake gh stub via PATH
  local bin_dir="$SANDBOX_ROOT/bin"
  mkdir -p "$bin_dir"
  # Create a wrapper script rather than a symlink — more portable, and lets us
  # inject the GH_STATE_FILE env var reliably across subshells.
  cat > "$bin_dir/gh" <<WRAPPER
#!/usr/bin/env bash
exec bash "$_FAKE_GH" "\$@"
WRAPPER
  chmod +x "$bin_dir/gh"

  # Prepend the stub bin to PATH for this process and all subprocesses
  export PATH="$bin_dir:$PATH"

  # Initialise empty stub state
  e2e_reset_state
}

# ---------------------------------------------------------------------------
# e2e_teardown
#
# Removes the entire sandbox. Called by the EXIT trap — tests should not call
# this directly.
# ---------------------------------------------------------------------------
e2e_teardown() {
  if [[ -n "${SANDBOX_ROOT:-}" && -d "$SANDBOX_ROOT" ]]; then
    rm -rf "$SANDBOX_ROOT"
  fi
}

# ---------------------------------------------------------------------------
# e2e_reset_state
#
# Writes a fresh empty gh-state.json. Useful when a single test file runs
# multiple independent scenarios and needs to reset issue/PR state between
# them without tearing down the entire sandbox.
# ---------------------------------------------------------------------------
e2e_reset_state() {
  cat > "$GH_STATE_FILE" <<'JSON'
{
  "issues": {},
  "prs": {},
  "next_issue_number": 1,
  "next_pr_number": 1
}
JSON
}

# ---------------------------------------------------------------------------
# e2e_create_issue <title> <body> <labels_csv>
#
# Creates an issue in the stub state. Prints the new issue number to stdout.
# labels_csv: comma-separated label names, e.g. "bug,in-progress"
# ---------------------------------------------------------------------------
e2e_create_issue() {
  local title="$1"
  local body="${2:-}"
  local labels_csv="${3:-}"

  # Build labels JSON array from CSV
  local labels_json
  if [[ -n "$labels_csv" ]]; then
    labels_json="$(printf '%s' "$labels_csv" | tr ',' '\n' | jq -Rn '[inputs | select(length>0)]')"
  else
    labels_json="[]"
  fi

  local num
  num="$(jq -r '.next_issue_number' "$GH_STATE_FILE")"

  jq --arg num "$num" \
     --arg title "$title" \
     --arg body "$body" \
     --argjson labels "$labels_json" \
     '.issues[$num] = {
       "number": ($num | tonumber),
       "title": $title,
       "body": $body,
       "state": "open",
       "labels": $labels,
       "comments": []
     } |
     .next_issue_number = (.next_issue_number + 1)' \
     "$GH_STATE_FILE" > "$GH_STATE_FILE.tmp" && mv "$GH_STATE_FILE.tmp" "$GH_STATE_FILE"

  printf '%s\n' "$num"
}

# ---------------------------------------------------------------------------
# e2e_add_label <number> <type> <label>
# e2e_remove_label <number> <type> <label>
#
# Add/remove a label from an issue or PR in stub state.
# type: "issue" | "pr"
# ---------------------------------------------------------------------------
e2e_add_label() {
  local num="$1"
  local type="$2"  # "issue" or "pr"
  local label="$3"

  local key
  if [[ "$type" == "issue" ]]; then key="issues"; else key="prs"; fi

  jq --arg num "$num" --arg label "$label" --arg key "$key" \
    '.[$key][$num].labels = ((.[$key][$num].labels // []) + [$label] | unique)' \
    "$GH_STATE_FILE" > "$GH_STATE_FILE.tmp" && mv "$GH_STATE_FILE.tmp" "$GH_STATE_FILE"
}

e2e_remove_label() {
  local num="$1"
  local type="$2"
  local label="$3"

  local key
  if [[ "$type" == "issue" ]]; then key="issues"; else key="prs"; fi

  jq --arg num "$num" --arg label "$label" --arg key "$key" \
    '.[$key][$num].labels = ((.[$key][$num].labels // []) | map(select(. != $label)))' \
    "$GH_STATE_FILE" > "$GH_STATE_FILE.tmp" && mv "$GH_STATE_FILE.tmp" "$GH_STATE_FILE"
}

# ---------------------------------------------------------------------------
# e2e_close_issue <issue_num>
#
# Marks an issue closed in stub state (direct state mutation, not via PR body).
# ---------------------------------------------------------------------------
e2e_close_issue() {
  local num="$1"
  jq --arg num "$num" \
    '.issues[$num].state = "closed"' \
    "$GH_STATE_FILE" > "$GH_STATE_FILE.tmp" && mv "$GH_STATE_FILE.tmp" "$GH_STATE_FILE"
}

# ---------------------------------------------------------------------------
# e2e_create_pr <title> <body> <head_branch> <base_branch>
#
# Creates a PR in stub state. Prints the new PR number to stdout.
# The PR is initialised with state "open".
# ---------------------------------------------------------------------------
e2e_create_pr() {
  local title="$1"
  local body="${2:-}"
  local head_branch="$3"
  local base_branch="${4:-main}"

  local num
  num="$(jq -r '.next_pr_number' "$GH_STATE_FILE")"

  jq --arg num "$num" \
     --arg title "$title" \
     --arg body "$body" \
     --arg head "$head_branch" \
     --arg base "$base_branch" \
     '.prs[$num] = {
       "number": ($num | tonumber),
       "title": $title,
       "body": $body,
       "state": "open",
       "head_branch": $head,
       "base_branch": $base,
       "labels": [],
       "comments": [],
       "merged_at": null
     } |
     .next_pr_number = (.next_pr_number + 1)' \
     "$GH_STATE_FILE" > "$GH_STATE_FILE.tmp" && mv "$GH_STATE_FILE.tmp" "$GH_STATE_FILE"

  printf '%s\n' "$num"
}

# ---------------------------------------------------------------------------
# e2e_merge_pr <pr_num>
#
# Simulates merging a PR:
#   - Sets PR state → "merged" and merged_at → timestamp
#   - Scans PR body for "Closes #N" (case-insensitive); closes those issues
#   - Deletes the remote branch (push --delete to the bare repo)
#
# Does NOT enforce Hook 6 — hook enforcement is tested separately via run_case
# from lib.sh. By the time this helper is called, the test has already asserted
# that Hook 6 would allow the command.
# ---------------------------------------------------------------------------
e2e_merge_pr() {
  local pr_num="$1"

  local pr_json
  pr_json="$(jq --arg n "$pr_num" '.prs[$n]' "$GH_STATE_FILE")"

  local head_branch
  head_branch="$(printf '%s' "$pr_json" | jq -r '.head_branch')"

  local body
  body="$(printf '%s' "$pr_json" | jq -r '.body')"

  # Mark PR as merged
  local timestamp="2026-05-22T00:00:00Z"
  jq --arg num "$pr_num" --arg ts "$timestamp" \
    '.prs[$num].state = "merged" | .prs[$num].merged_at = $ts' \
    "$GH_STATE_FILE" > "$GH_STATE_FILE.tmp" && mv "$GH_STATE_FILE.tmp" "$GH_STATE_FILE"

  # Simulate Closes #N auto-close: find all "Closes #<num>" in body
  local closes_nums
  closes_nums="$(printf '%s' "$body" | grep -oiE 'closes[[:space:]]+#[0-9]+' | grep -oE '[0-9]+')"
  for issue_num in $closes_nums; do
    jq --arg n "$issue_num" \
      '.issues[$n].state = "closed"' \
      "$GH_STATE_FILE" > "$GH_STATE_FILE.tmp" && mv "$GH_STATE_FILE.tmp" "$GH_STATE_FILE"
  done

  # Delete the remote branch (push --delete to the bare origin)
  if [[ -n "$head_branch" && "$head_branch" != "null" ]]; then
    git -C "$SANDBOX_WORK" push --quiet origin --delete "$head_branch" 2>/dev/null || true
    # Also delete the local tracking ref
    git -C "$SANDBOX_WORK" branch -D "$head_branch" 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# e2e_add_comment <number> <type> <comment_text>
#
# Appends a comment to an issue or PR in stub state.
# type: "issue" | "pr"
# ---------------------------------------------------------------------------
e2e_add_comment() {
  local num="$1"
  local type="$2"
  local comment="$3"

  local key
  if [[ "$type" == "issue" ]]; then key="issues"; else key="prs"; fi

  jq --arg num "$num" --arg comment "$comment" --arg key "$key" \
    '.[$key][$num].comments = ((.[$key][$num].comments // []) + [$comment])' \
    "$GH_STATE_FILE" > "$GH_STATE_FILE.tmp" && mv "$GH_STATE_FILE.tmp" "$GH_STATE_FILE"
}

# ---------------------------------------------------------------------------
# e2e_create_worktree <task_id> <branch_name>
#
# Creates a new branch in the sandbox and adds a git worktree at
# $SANDBOX_WORK/.worktrees/<task_id>. The branch is based on origin/main.
# ---------------------------------------------------------------------------
e2e_create_worktree() {
  local task_id="$1"
  local branch_name="$2"

  git -C "$SANDBOX_WORK" fetch --quiet origin
  git -C "$SANDBOX_WORK" worktree add \
    ".worktrees/$task_id" \
    -b "$branch_name" \
    origin/main \
    --quiet 2>/dev/null
}

# ---------------------------------------------------------------------------
# e2e_remove_worktree <task_id>
#
# Removes the worktree at $SANDBOX_WORK/.worktrees/<task_id>, prunes worktree
# metadata, and deletes the local branch that the worktree was on.
#
# This mirrors the post-merge cleanup that Dev agents must perform manually:
# `git worktree remove .worktrees/<task-id>` followed by `git branch -D <branch>`.
# The branch cannot be deleted BEFORE the worktree is removed (git refuses to
# delete a branch checked out in a worktree), which is why this helper handles
# both steps in the correct order.
# ---------------------------------------------------------------------------
e2e_remove_worktree() {
  local task_id="$1"

  # Discover which branch this worktree is on before removing it
  local wt_path="$SANDBOX_WORK/.worktrees/$task_id"
  local branch_name=""
  if [[ -d "$wt_path" ]]; then
    branch_name="$(git -C "$wt_path" symbolic-ref --short HEAD 2>/dev/null || true)"
  fi

  # Remove the worktree directory and prune stale refs
  git -C "$SANDBOX_WORK" worktree remove ".worktrees/$task_id" --force 2>/dev/null || true
  git -C "$SANDBOX_WORK" worktree prune 2>/dev/null || true

  # Now that the worktree is gone, delete the local branch if we found one
  if [[ -n "$branch_name" ]]; then
    git -C "$SANDBOX_WORK" branch -D "$branch_name" 2>/dev/null || true
  fi
}

# ===========================================================================
# ASSERTION HELPERS
#
# All helpers print PASS/FAIL and update the $PASS/$FAIL counters (inherited
# from lib.sh, which the caller must source before lib_e2e.sh).
# ===========================================================================

# ---------------------------------------------------------------------------
# assert_label_present <label> <number> <type>
# assert_label_absent  <label> <number> <type>
#
# type: "issue" | "pr"
# ---------------------------------------------------------------------------
assert_label_present() {
  local label="$1"
  local num="$2"
  local type="${3:-issue}"

  local key
  if [[ "$type" == "issue" ]]; then key="issues"; else key="prs"; fi

  local present
  present="$(jq -r --arg n "$num" --arg l "$label" --arg k "$key" \
    '(.[$k][$n].labels // []) | any(. == $l) | if . then "yes" else "no" end' \
    "$GH_STATE_FILE")"

  local label_desc
  label_desc="label '$label' present on $type #$num"
  if [[ "$present" == "yes" ]]; then
    printf '  PASS  %s\n' "$label_desc"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  %s\n' "$label_desc"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_label_absent() {
  local label="$1"
  local num="$2"
  local type="${3:-issue}"

  local key
  if [[ "$type" == "issue" ]]; then key="issues"; else key="prs"; fi

  local present
  present="$(jq -r --arg n "$num" --arg l "$label" --arg k "$key" \
    '(.[$k][$n].labels // []) | any(. == $l) | if . then "yes" else "no" end' \
    "$GH_STATE_FILE")"

  local label_desc
  label_desc="label '$label' absent on $type #$num"
  if [[ "$present" == "no" ]]; then
    printf '  PASS  %s\n' "$label_desc"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  %s\n' "$label_desc"
    FAIL=$(( FAIL + 1 ))
  fi
}

# ---------------------------------------------------------------------------
# assert_issue_open <issue_num>
# assert_issue_closed <issue_num>
# ---------------------------------------------------------------------------
assert_issue_open() {
  local num="$1"
  local state
  state="$(jq -r --arg n "$num" '.issues[$n].state // "missing"' "$GH_STATE_FILE")"
  if [[ "$state" == "open" ]]; then
    printf '  PASS  issue #%s is open\n' "$num"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  issue #%s expected open, got: %s\n' "$num" "$state"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_issue_closed() {
  local num="$1"
  local state
  state="$(jq -r --arg n "$num" '.issues[$n].state // "missing"' "$GH_STATE_FILE")"
  if [[ "$state" == "closed" ]]; then
    printf '  PASS  issue #%s is closed\n' "$num"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  issue #%s expected closed, got: %s\n' "$num" "$state"
    FAIL=$(( FAIL + 1 ))
  fi
}

# ---------------------------------------------------------------------------
# assert_pr_state <pr_num> <expected_state>
#
# Valid states: "open", "merged", "closed"
# ---------------------------------------------------------------------------
assert_pr_state() {
  local num="$1"
  local expected="$2"
  local actual
  actual="$(jq -r --arg n "$num" '.prs[$n].state // "missing"' "$GH_STATE_FILE")"
  if [[ "$actual" == "$expected" ]]; then
    printf '  PASS  PR #%s state is %s\n' "$num" "$expected"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  PR #%s expected state=%s, got: %s\n' "$num" "$expected" "$actual"
    FAIL=$(( FAIL + 1 ))
  fi
}

# ---------------------------------------------------------------------------
# assert_worktree_exists <task_id>
# assert_worktree_removed <task_id>
# ---------------------------------------------------------------------------
assert_worktree_exists() {
  local task_id="$1"
  local path="$SANDBOX_WORK/.worktrees/$task_id"
  if [[ -d "$path" ]]; then
    printf '  PASS  worktree .worktrees/%s exists\n' "$task_id"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  worktree .worktrees/%s expected to exist but does not\n' "$task_id"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_worktree_removed() {
  local task_id="$1"
  local path="$SANDBOX_WORK/.worktrees/$task_id"
  if [[ ! -d "$path" ]]; then
    printf '  PASS  worktree .worktrees/%s is gone\n' "$task_id"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  worktree .worktrees/%s expected to be gone but still exists\n' "$task_id"
    FAIL=$(( FAIL + 1 ))
  fi
}

# ---------------------------------------------------------------------------
# assert_branch_exists <branch_name>
# assert_branch_deleted <branch_name>
#
# Checks local branch existence in $SANDBOX_WORK.
# ---------------------------------------------------------------------------
assert_branch_exists() {
  local branch="$1"
  if git -C "$SANDBOX_WORK" rev-parse --verify "refs/heads/$branch" &>/dev/null; then
    printf '  PASS  local branch %s exists\n' "$branch"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  local branch %s expected to exist but does not\n' "$branch"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_branch_deleted() {
  local branch="$1"
  if ! git -C "$SANDBOX_WORK" rev-parse --verify "refs/heads/$branch" &>/dev/null; then
    printf '  PASS  local branch %s is gone\n' "$branch"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  local branch %s expected to be gone but still exists\n' "$branch"
    FAIL=$(( FAIL + 1 ))
  fi
}

# ---------------------------------------------------------------------------
# assert_remote_branch_deleted <branch_name>
#
# Checks that the branch does NOT exist in origin ($SANDBOX_REPO).
# ---------------------------------------------------------------------------
assert_remote_branch_deleted() {
  local branch="$1"
  if ! git -C "$SANDBOX_REPO" rev-parse --verify "refs/heads/$branch" &>/dev/null; then
    printf '  PASS  remote branch %s is gone\n' "$branch"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  remote branch %s expected to be gone but still exists on origin\n' "$branch"
    FAIL=$(( FAIL + 1 ))
  fi
}

# ---------------------------------------------------------------------------
# assert_pr_body_contains <pr_num> <substring>
#
# Verifies the PR body contains <substring>. Used to check Closes #N / Refs #N
# discipline.
# ---------------------------------------------------------------------------
assert_pr_body_contains() {
  local num="$1"
  local substring="$2"
  local body
  body="$(jq -r --arg n "$num" '.prs[$n].body // ""' "$GH_STATE_FILE")"
  if printf '%s' "$body" | grep -qF "$substring"; then
    printf '  PASS  PR #%s body contains: %s\n' "$num" "$substring"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  PR #%s body does not contain: %s\n' "$num" "$substring"
    FAIL=$(( FAIL + 1 ))
  fi
}

# ---------------------------------------------------------------------------
# assert_comment_present <number> <type> <substring>
#
# PASS if any comment on the issue or PR contains <substring>.
# type: "issue" | "pr"
# ---------------------------------------------------------------------------
assert_comment_present() {
  local num="$1"
  local type="$2"
  local substring="$3"

  local key
  if [[ "$type" == "issue" ]]; then key="issues"; else key="prs"; fi

  local found
  found="$(jq -r --arg n "$num" --arg k "$key" --arg sub "$substring" \
    '(.[$k][$n].comments // []) | any(test($sub; "i")) | if . then "yes" else "no" end' \
    "$GH_STATE_FILE")"

  if [[ "$found" == "yes" ]]; then
    printf '  PASS  comment containing "%s" present on %s #%s\n' "$substring" "$type" "$num"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  no comment containing "%s" on %s #%s\n' "$substring" "$type" "$num"
    FAIL=$(( FAIL + 1 ))
  fi
}
