#!/usr/bin/env bash
# auto-clean-worktree.sh — Hook 7 of 12
#
# PostToolUse / Bash hook: after a successful `gh pr merge`, find any
# `.worktrees/` entry whose checked-out branch matches the merged PR's
# head branch, remove the worktree, then delete the now-detached local
# branch.
#
# Why PostToolUse instead of PreToolUse?
#   Cleanup must happen AFTER the merge succeeds, not before. PreToolUse
#   cannot know whether the merge will succeed. PostToolUse fires after the
#   Bash tool returns, so `tool_response` confirms success.
#
# Ordering constraint (CR Slice 5 review note):
#   `git branch -D <branch>` fails if a worktree still has that branch
#   checked out: "Cannot delete branch '...' checked out at '...'".
#   This hook always removes the worktree FIRST, then deletes the branch.
#
# Safety:
#   - Checks for uncommitted changes (`git status --porcelain`) before
#     removing a worktree. If dirty, logs a WARNING and skips that worktree.
#   - If no matching worktree exists (Dev already cleaned up manually), logs
#     nothing — that is valid state, not an error.
#   - Always exits 0. This hook must never block the agent's workflow.
#
# stdin shape (PostToolUse) — real Claude Code runtime fields (issue #81 fix):
#   {
#     "tool_name": "Bash",
#     "tool_input": { "command": "<bash command string>" },
#     "tool_response": { "stdout": "<stdout>", "stderr": "<stderr>", "exit_code": <int> }
#   }
#
# NOTE: The runtime sends "stdout"/"stderr"/"exit_code" — NOT "output"/"error".
# The original implementation read the wrong field names (issue #81, hypothesis 2).
#
# LIMITATION (issue #81, hypothesis 1 — the primary cause):
#   PostToolUse hooks registered in settings.json do NOT fire for tool calls
#   made inside agent sub-sessions (anthropics/claude-code #34692). This hook
#   only fires when the operator's main session runs `gh pr merge` directly.
#   For CR-agent merges (99% of real merges), use `bin/merge-pr.sh` instead,
#   which includes the cleanup logic explicitly and works in all contexts.
#
# Environment overrides (for test isolation):
#   CLAUDE_HOOK_BYPASS=1                 — skip all checks (ops emergency)
#   CLAUDE_HOOK_TEST_REPO_ROOT=<dir>     — override repo root (default: git toplevel)
#   CLAUDE_HOOK_TEST_GH_BRANCH_CMD=<cmd> — override `gh pr view ... --jq .headRefName`
#
# Tests: tests/test_hooks.sh Hook 7 section + tests/test_e2e_hook7_worktree_cleanup.sh
# Full docs: .claude/hooks/README.md

set -euo pipefail

# ---------------------------------------------------------------------------
# HELPER — cleanup_worktree <path> <branch> <repo_root>
# Remove one worktree and its local branch.
# Must be defined before the main flow that calls it.
# ---------------------------------------------------------------------------
cleanup_worktree() {
  local wt_path="$1"
  local branch="$2"
  local repo_root="$3"

  # Safety: refuse to remove a worktree with uncommitted changes.
  if git -C "$wt_path" rev-parse --git-dir &>/dev/null 2>&1; then
    local dirty
    dirty="$(git -C "$wt_path" status --porcelain 2>/dev/null || true)"
    if [[ -n "$dirty" ]]; then
      echo "[auto-clean-worktree] WARNING: worktree '${wt_path}' has uncommitted changes — skipping removal." >&2
      return 0
    fi
  fi

  # Remove worktree FIRST (ordering constraint — branch cannot be deleted
  # while a worktree has it checked out).
  echo "[auto-clean-worktree] Removing worktree: ${wt_path} (branch: ${branch})" >&2
  if git -C "$repo_root" worktree remove "$wt_path" 2>/dev/null; then
    echo "[auto-clean-worktree] Worktree removed: ${wt_path}" >&2
  else
    echo "[auto-clean-worktree] WARNING: failed to remove worktree '${wt_path}' — manual cleanup required." >&2
    return 0
  fi

  # Delete local branch now that no worktree holds it.
  echo "[auto-clean-worktree] Deleting local branch: ${branch}" >&2
  if git -C "$repo_root" branch -D "$branch" 2>/dev/null; then
    echo "[auto-clean-worktree] Branch deleted: ${branch}" >&2
  else
    echo "[auto-clean-worktree] WARNING: failed to delete branch '${branch}' — manual cleanup required." >&2
  fi
}

# ---------------------------------------------------------------------------
# SECTION 0 — Bypass
# ---------------------------------------------------------------------------
if [[ "${CLAUDE_HOOK_BYPASS:-}" == "1" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# SECTION 1 — Parse stdin
# ---------------------------------------------------------------------------
INPUT="$(cat)"

if ! command -v jq &>/dev/null; then
  echo "[auto-clean-worktree] WARNING: jq not found — hook skipped." >&2
  exit 0
fi

COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')"

if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# SECTION 2 — Is this a gh pr merge command?
# Same detection regex as Hook 6 (anchored to shell-segment start).
# ---------------------------------------------------------------------------
GH_MERGE_RE='(^|;|&&|\|\||[|])[[:space:]]*gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)'
if ! printf '%s' "$COMMAND" | command grep -qE "$GH_MERGE_RE"; then
  exit 0
fi

# ---------------------------------------------------------------------------
# SECTION 3 — Did the command succeed?
# PostToolUse stdin includes tool_response with fields: stdout, stderr, exit_code
# (issue #81 fix: original code read .tool_response.error and .tool_response.output
# which are NOT the real field names; corrected to .stderr and .stdout).
#
# We check:
#   (a) exit_code != 0 AND merge failure phrases in stderr — hard skip.
#   (b) stdout/stderr contains "not merged|failed to merge|^error" phrases.
#
# We do NOT bail on non-zero exit_code alone, because `gh pr merge` may return
# exit code 1 when the GitHub merge succeeded but local branch deletion failed
# (the "Cannot delete branch ... checked out at ..." constraint). In that case
# the merge was real and cleanup should still proceed.
# ---------------------------------------------------------------------------
TOOL_STDERR="$(printf '%s' "$INPUT" | jq -r '.tool_response.stderr // .tool_response.error // ""')"
TOOL_STDOUT="$(printf '%s' "$INPUT" | jq -r '.tool_response.stdout // .tool_response.output // ""')"
EXIT_CODE="$(printf '%s' "$INPUT" | jq -r '.tool_response.exit_code // 0')"

# Hard failure: non-zero exit AND known merge-failure phrases in stderr.
# Accepting non-zero exit alone would be too aggressive (see above).
if [[ "$EXIT_CODE" != "0" ]] && \
   printf '%s' "$TOOL_STDERR" | command grep -qiE 'not merged|failed to merge|pull request.*not found|no pull requests found'; then
  exit 0
fi

# Output-level failure indicators (cover gh printing errors to stdout too).
COMBINED_OUTPUT="${TOOL_STDOUT}${TOOL_STDERR}"
if printf '%s' "$COMBINED_OUTPUT" | command grep -qiE 'not merged|failed to merge|pull request.*not found'; then
  exit 0
fi

# ---------------------------------------------------------------------------
# SECTION 4 — Extract the PR number from the command
# Same token-walking algorithm as Hook 3.
# ---------------------------------------------------------------------------
MERGE_SEGMENT="$(printf '%s' "$COMMAND" | command grep -oE 'gh[[:space:]]+pr[[:space:]]+merge([[:space:]].*)?$' | head -1)"

if [[ -z "$MERGE_SEGMENT" ]]; then
  exit 0
fi

AFTER_MERGE="${MERGE_SEGMENT#*merge}"
AFTER_MERGE="${AFTER_MERGE#"${AFTER_MERGE%%[! ]*}"}"

PR_NUM=""
for token in $AFTER_MERGE; do
  if [[ "$token" == -* ]]; then
    continue
  fi
  # Strip surrounding shell quotes
  if [[ ( "$token" == \'*\' ) || ( "$token" == \"*\" ) ]]; then
    token="${token:1:${#token}-2}"
  fi
  # URL form: extract trailing integer after pull/
  if printf '%s' "$token" | command grep -qE 'pull/[0-9]+'; then
    PR_NUM="$(printf '%s' "$token" | command grep -oE 'pull/[0-9]+' | command grep -oE '[0-9]+$')"
    break
  fi
  # Bare integer
  if printf '%s' "$token" | command grep -qE '^[0-9]+$'; then
    PR_NUM="$token"
    break
  fi
  # Non-flag, non-numeric (branch name or HEAD) — cannot look up without PR number.
  exit 0
done

if [[ -z "$PR_NUM" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# SECTION 5 — Fetch the head branch name for this PR
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
  echo "[auto-clean-worktree] WARNING: could not determine head branch for PR #${PR_NUM} — skipping cleanup." >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# SECTION 6 — Resolve repo root and confirm .worktrees/ exists
# ---------------------------------------------------------------------------
REPO_ROOT="${CLAUDE_HOOK_TEST_REPO_ROOT:-}"
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "$REPO_ROOT" ]]; then
  echo "[auto-clean-worktree] WARNING: cannot determine repo root — skipping cleanup." >&2
  exit 0
fi

WORKTREES_DIR="${REPO_ROOT}/.worktrees"

if [[ ! -d "$WORKTREES_DIR" ]]; then
  # No .worktrees directory — nothing to clean.
  exit 0
fi

# Canonicalize WORKTREES_DIR to handle macOS /var → /private/var symlinks.
# git worktree list --porcelain returns resolved paths; we must compare apples to apples.
WORKTREES_DIR_REAL="$(cd "$WORKTREES_DIR" && pwd -P)"

# ---------------------------------------------------------------------------
# SECTION 7 — Scan git worktree list for entries on HEAD_BRANCH
#
# `git worktree list --porcelain` produces blocks separated by blank lines:
#   worktree /path
#   HEAD <sha>
#   branch refs/heads/<name>
#       -or-
#   detached
# ---------------------------------------------------------------------------
GIT_WORKTREE_LIST=""
if git -C "$REPO_ROOT" rev-parse --git-dir &>/dev/null 2>&1; then
  GIT_WORKTREE_LIST="$(git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null || true)"
fi

CLEANED_ANYTHING=0
CURRENT_PATH=""
CURRENT_BRANCH=""

while IFS= read -r line; do
  if [[ "$line" == worktree\ * ]]; then
    CURRENT_PATH="${line#worktree }"
    CURRENT_BRANCH=""
  elif [[ "$line" == branch\ refs/heads/* ]]; then
    CURRENT_BRANCH="${line#branch refs/heads/}"
  elif [[ -z "$line" && -n "$CURRENT_PATH" ]]; then
    # End of block — check for match
    if [[ "$CURRENT_BRANCH" == "$HEAD_BRANCH" && \
          "$CURRENT_PATH" == "${WORKTREES_DIR_REAL}/"* ]]; then
      cleanup_worktree "$CURRENT_PATH" "$CURRENT_BRANCH" "$REPO_ROOT" || true
      CLEANED_ANYTHING=1
    fi
    CURRENT_PATH=""
    CURRENT_BRANCH=""
  fi
done <<< "$GIT_WORKTREE_LIST"

# Handle last block (git worktree list --porcelain has no trailing blank line).
if [[ -n "$CURRENT_PATH" && \
      "$CURRENT_BRANCH" == "$HEAD_BRANCH" && \
      "$CURRENT_PATH" == "${WORKTREES_DIR_REAL}/"* ]]; then
  cleanup_worktree "$CURRENT_PATH" "$CURRENT_BRANCH" "$REPO_ROOT" || true
  CLEANED_ANYTHING=1
fi

# CLEANED_ANYTHING=0 is not an error — Dev may have already cleaned up.

exit 0
