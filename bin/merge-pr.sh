#!/usr/bin/env bash
# bin/merge-pr.sh — safe PR merge with guaranteed post-merge worktree cleanup.
#
# WHY THIS SCRIPT EXISTS (Issue #81):
#   PostToolUse hooks registered in .claude/settings.json do NOT fire for
#   tool calls made inside agent sub-sessions (GitHub issue anthropics/claude-code
#   #34692, confirmed March 2026). Hook 7 (auto-clean-worktree.sh) relies on
#   PostToolUse, so it was silently skipped for every CR-agent merge — which
#   is 99% of real merges in this SDLC. This script replaces the purely
#   mechanical hook dependency with an explicit cleanup step that runs in any
#   context (main session, agent sub-session, CI).
#
# USAGE (Code Reviewer agent — Step 7 of SDLC.md):
#
#   bin/merge-pr.sh <PR-NUMBER> [--squash] [--rebase] [--merge]
#
#   Examples:
#     bin/merge-pr.sh 42
#     bin/merge-pr.sh 42 --squash       ← default / recommended
#     bin/merge-pr.sh 42 --squash --admin
#
#   Always passes --delete-branch to gh (enforced by Hook 6 too).
#
# WHAT IT DOES:
#   1. Runs `gh pr merge <N> --delete-branch <extra-flags>`.
#   2. If the merge succeeds on GitHub (confirmed by parsing gh output for the
#      "Merged pull request" string), looks up the merged head-branch name.
#   3. Calls the cleanup logic from auto-clean-worktree.sh to remove the
#      matching .worktrees/ entry and local branch.
#   4. If the merge itself failed, exits non-zero without attempting cleanup.
#
# EXIT CODES:
#   0 — merge succeeded (cleanup attempted, worktree removed if found)
#   1 — gh pr merge failed (GitHub merge did not go through)
#
# ENVIRONMENT OVERRIDES (test isolation — same as auto-clean-worktree.sh):
#   CLAUDE_HOOK_BYPASS=1                 — skip all checks (ops emergency)
#   CLAUDE_HOOK_TEST_REPO_ROOT=<dir>     — override repo root
#   CLAUDE_HOOK_TEST_GH_BRANCH_CMD=<cmd> — override `gh pr view <N> --json headRefName` call
#   CLAUDE_HOOK_TEST_MERGE_CMD=<cmd>     — override `gh pr merge` itself
#     stub receives: <pr_num> --delete-branch <extra-flags...>
#     must print merge output to stdout (include "Merged pull request" on success)
#     must exit 0 on success, non-zero on failure
#   CLAUDE_HOOK_TEST_PR_STATE_CMD=<cmd>  — override `gh pr view <N> --json state` call
#     stub receives: <pr_num>
#     must print the PR state string to stdout ("MERGED", "OPEN", "CLOSED", etc.)
#     used by Section 3 fallback to detect remote merge success in non-TTY contexts

set -euo pipefail

# ---------------------------------------------------------------------------
# SECTION 0 — Bypass
# ---------------------------------------------------------------------------
if [[ "${CLAUDE_HOOK_BYPASS:-}" == "1" ]]; then
  # Fall through to plain gh pr merge (no cleanup) for ops emergency.
  exec gh pr merge "$@" --delete-branch
fi

# ---------------------------------------------------------------------------
# SECTION 1 — Parse arguments
# Extract the PR number from positional args; forward remaining flags.
# ---------------------------------------------------------------------------
PR_NUM=""
EXTRA_FLAGS=()
POSITIONAL_DONE=0

for arg in "$@"; do
  if [[ "$POSITIONAL_DONE" -eq 0 && "$arg" != -* ]]; then
    # Could be a bare PR number or URL (first non-flag argument)
    # URL form: extract trailing integer after pull/
    if printf '%s' "$arg" | grep -qE 'pull/[0-9]+'; then
      PR_NUM="$(printf '%s' "$arg" | grep -oE 'pull/[0-9]+' | grep -oE '[0-9]+$')"
    elif printf '%s' "$arg" | grep -qE '^[0-9]+$'; then
      PR_NUM="$arg"
    fi
    POSITIONAL_DONE=1
    EXTRA_FLAGS+=("$arg")
  else
    EXTRA_FLAGS+=("$arg")
  fi
done

if [[ -z "$PR_NUM" ]]; then
  printf '[merge-pr] ERROR: could not determine PR number from arguments: %s\n' "$*" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# SECTION 2 — Run the merge
# ---------------------------------------------------------------------------
run_merge() {
  if [[ -n "${CLAUDE_HOOK_TEST_MERGE_CMD:-}" ]]; then
    bash -c "${CLAUDE_HOOK_TEST_MERGE_CMD} ${PR_NUM} --delete-branch ${EXTRA_FLAGS[*]:-}"
  else
    # Always include --delete-branch (Hook 6 also enforces this, but belt-and-suspenders)
    gh pr merge "${EXTRA_FLAGS[@]}" --delete-branch
  fi
}

printf '[merge-pr] Merging PR #%s...\n' "$PR_NUM" >&2

MERGE_OUTPUT=""
MERGE_EXIT=0
MERGE_OUTPUT="$(run_merge 2>&1)" || MERGE_EXIT=$?

# Print whatever gh printed (could be a success message or error detail)
printf '%s\n' "$MERGE_OUTPUT"

# ---------------------------------------------------------------------------
# SECTION 3 — Did the merge succeed on GitHub?
#
# Three-tier success detection (in order):
#
# Tier 1 — Banner match: gh printed "Merged pull request" on stdout.
#   Fast path. Works when gh runs in a TTY or when stdout is not captured.
#
# Tier 2 — Exit 0 without banner: gh exited 0 without printing the banner.
#   Covers older gh versions that don't print the string; trust exit code 0.
#
# Tier 3 — Remote state check (Issue #87 fix): both tier 1 and tier 2 failed.
#   This happens when gh v2.89.0+ suppresses the banner in a non-TTY subshell
#   AND exits non-zero because the local-branch delete failed (the branch is
#   checked out in a sibling worktree). In this case the GitHub-side merge
#   already succeeded. We verify by calling `gh pr view <N> --json state` —
#   if the remote state is "MERGED", treat as success and proceed to cleanup.
#   One extra API call per merge, which is cheap and TTY-independent.
# ---------------------------------------------------------------------------
fetch_pr_state() {
  local pr_num="$1"
  if [[ -n "${CLAUDE_HOOK_TEST_PR_STATE_CMD:-}" ]]; then
    bash -c "${CLAUDE_HOOK_TEST_PR_STATE_CMD} ${pr_num}"
  else
    gh pr view "$pr_num" --json state --jq '.state' 2>/dev/null || true
  fi
}

MERGE_SUCCEEDED=0
if printf '%s' "$MERGE_OUTPUT" | grep -qiE 'Merged pull request|merged PR'; then
  # Tier 1 — banner present in output
  MERGE_SUCCEEDED=1
elif [[ "$MERGE_EXIT" -eq 0 ]]; then
  # Tier 2 — exit 0, no banner (older gh)
  MERGE_SUCCEEDED=1
else
  # Tier 3 — non-TTY banner suppression + local-branch checkout conflict.
  # Ask GitHub directly whether the PR merged.
  PR_STATE="$(fetch_pr_state "$PR_NUM")"
  if [[ "$PR_STATE" == "MERGED" ]]; then
    printf '[merge-pr] Remote state=MERGED for PR #%s (gh exited %s, no banner) — proceeding with cleanup.\n' \
      "$PR_NUM" "$MERGE_EXIT" >&2
    MERGE_SUCCEEDED=1
  fi
fi

if [[ "$MERGE_SUCCEEDED" -eq 0 ]]; then
  printf '[merge-pr] Merge failed for PR #%s — skipping cleanup.\n' "$PR_NUM" >&2
  exit "$MERGE_EXIT"
fi

printf '[merge-pr] Merge confirmed for PR #%s — running worktree cleanup.\n' "$PR_NUM" >&2

# ---------------------------------------------------------------------------
# SECTION 4 — Fetch the head branch name for this PR
# ---------------------------------------------------------------------------
fetch_head_branch() {
  local pr_num="$1"
  if [[ -n "${CLAUDE_HOOK_TEST_GH_BRANCH_CMD:-}" ]]; then
    bash -c "${CLAUDE_HOOK_TEST_GH_BRANCH_CMD} ${pr_num}"
  else
    gh pr view "$pr_num" --json headRefName --jq '.headRefName' 2>/dev/null || true
  fi
}

HEAD_BRANCH="$(fetch_head_branch "$PR_NUM")"

if [[ -z "$HEAD_BRANCH" ]]; then
  printf '[merge-pr] WARNING: could not determine head branch for PR #%s — skipping cleanup.\n' "$PR_NUM" >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# SECTION 5 — Resolve repo root and confirm .worktrees/ exists
# Same logic as auto-clean-worktree.sh Section 6.
# ---------------------------------------------------------------------------
REPO_ROOT="${CLAUDE_HOOK_TEST_REPO_ROOT:-}"
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "$REPO_ROOT" ]]; then
  printf '[merge-pr] WARNING: cannot determine repo root — skipping cleanup.\n' >&2
  exit 0
fi

WORKTREES_DIR="${REPO_ROOT}/.worktrees"
if [[ ! -d "$WORKTREES_DIR" ]]; then
  exit 0
fi
WORKTREES_DIR_REAL="$(cd "$WORKTREES_DIR" && pwd -P)"

# ---------------------------------------------------------------------------
# SECTION 6 — Cleanup helper (inline copy of auto-clean-worktree.sh's helper)
# Keeps this script self-contained so it works even if the hook isn't present.
# ---------------------------------------------------------------------------
cleanup_worktree() {
  local wt_path="$1"
  local branch="$2"
  local repo_root="$3"

  if git -C "$wt_path" rev-parse --git-dir &>/dev/null 2>&1; then
    local dirty
    dirty="$(git -C "$wt_path" status --porcelain 2>/dev/null || true)"
    if [[ -n "$dirty" ]]; then
      printf '[merge-pr] WARNING: worktree '"'"'%s'"'"' has uncommitted changes — skipping removal.\n' "$wt_path" >&2
      return 0
    fi
  fi

  printf '[merge-pr] Removing worktree: %s (branch: %s)\n' "$wt_path" "$branch" >&2
  if git -C "$repo_root" worktree remove "$wt_path" 2>/dev/null; then
    printf '[merge-pr] Worktree removed: %s\n' "$wt_path" >&2
  else
    printf '[merge-pr] WARNING: failed to remove worktree '"'"'%s'"'"' — manual cleanup required.\n' "$wt_path" >&2
    return 0
  fi

  printf '[merge-pr] Deleting local branch: %s\n' "$branch" >&2
  if git -C "$repo_root" branch -D "$branch" 2>/dev/null; then
    printf '[merge-pr] Branch deleted: %s\n' "$branch" >&2
  else
    printf '[merge-pr] WARNING: failed to delete branch '"'"'%s'"'"' — manual cleanup required.\n' "$branch" >&2
  fi
}

# ---------------------------------------------------------------------------
# SECTION 7 — Scan git worktree list for entries on HEAD_BRANCH
# Same scanning logic as auto-clean-worktree.sh Section 7.
# ---------------------------------------------------------------------------
GIT_WORKTREE_LIST=""
if git -C "$REPO_ROOT" rev-parse --git-dir &>/dev/null 2>&1; then
  GIT_WORKTREE_LIST="$(git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null || true)"
fi

CURRENT_PATH=""
CURRENT_BRANCH=""

while IFS= read -r line; do
  if [[ "$line" == worktree\ * ]]; then
    CURRENT_PATH="${line#worktree }"
    CURRENT_BRANCH=""
  elif [[ "$line" == branch\ refs/heads/* ]]; then
    CURRENT_BRANCH="${line#branch refs/heads/}"
  elif [[ -z "$line" && -n "$CURRENT_PATH" ]]; then
    if [[ "$CURRENT_BRANCH" == "$HEAD_BRANCH" && \
          "$CURRENT_PATH" == "${WORKTREES_DIR_REAL}/"* ]]; then
      cleanup_worktree "$CURRENT_PATH" "$CURRENT_BRANCH" "$REPO_ROOT" || true
    fi
    CURRENT_PATH=""
    CURRENT_BRANCH=""
  fi
done <<< "$GIT_WORKTREE_LIST"

# Handle last block (no trailing blank line)
if [[ -n "$CURRENT_PATH" && \
      "$CURRENT_BRANCH" == "$HEAD_BRANCH" && \
      "$CURRENT_PATH" == "${WORKTREES_DIR_REAL}/"* ]]; then
  cleanup_worktree "$CURRENT_PATH" "$CURRENT_BRANCH" "$REPO_ROOT" || true
fi

exit 0
