#!/usr/bin/env bash
# pr-merge-requires-in-review.sh — Hook 3 of 12
#
# PreToolUse / Bash hook: block `gh pr merge` when the PR does not carry
# the `in-review` label.
#
# Claude Code invokes this script for every Bash tool call. It receives a JSON
# object on stdin with the following shape (as of Claude Code hooks contract):
#
#   {
#     "tool_name": "Bash",
#     "tool_input": {
#       "command": "<the bash command string>"
#     }
#   }
#
# Exit codes:
#   0  — allow (silent)
#   2  — block (Claude Code surfaces stderr to the user)
#
# Smoke-test examples:
#   Block:   echo '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 5"}}' | bash pr-merge-requires-in-review.sh
#   Block:   echo '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --squash 5"}}' | bash pr-merge-requires-in-review.sh
#   Allow:   echo '{"tool_name":"Bash","tool_input":{"command":"gh pr view 5"}}' | bash pr-merge-requires-in-review.sh
#
# Tests live in tests/test_hooks.sh (run via bash tests/run.sh).
#
# Operator override: set CLAUDE_HOOK_BYPASS=1 to skip all checks.
#
# gh pr view stub: CLAUDE_HOOK_GH_LABELS_CMD overrides the label-fetching
# command. tests/fixtures/gh-labels-stub.sh provides a script-file stub
# that returns a controlled JSON array — no real GitHub API calls needed.
#
# See .claude/hooks/README.md for full escape-hatch documentation and
# .claude/skills/label-discipline/ for label ownership rules.

set -euo pipefail


# ---------------------------------------------------------------------------
# Normal hook mode
# ---------------------------------------------------------------------------

# --- Bypass for ops emergencies ---
if [[ "${CLAUDE_HOOK_BYPASS:-}" == "1" ]]; then
  exit 0
fi

# --- Read stdin ---
INPUT="$(cat)"

# Require jq; fail open (allow) if unavailable so the hook is never itself the blocker
if ! command -v jq &>/dev/null; then
  echo "[pr-merge-requires-in-review] WARNING: jq not found — hook skipped. Install jq to enable protection." >&2
  exit 0
fi

COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')"

# If we couldn't parse a command, allow through (don't break unrelated tool calls)
if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Detection: does this command contain `gh pr merge` as an actual command
# invocation (not inside a quoted argument of another command)?
#
# Strategy: require that `gh pr merge` appears at the start of the full
# command string OR immediately after a shell separator (;  &&  ||  |).
# This handles:
#   - Simple:    gh pr merge 5
#   - Compound:  cd /tmp && gh pr merge 5
# …and avoids false positives (spurious warnings) from:
#   - gh pr create --title "merge xyz"   ← 'merge' is an argument value
#   - grep "gh pr merge" SDLC.md         ← 'gh pr merge' is a grep argument
#
# We use grep -qE rather than bash regex to avoid bash ERE portability issues.
# ---------------------------------------------------------------------------
GH_MERGE_RE='(^|;|&&|\|\||[|])[[:space:]]*gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)'
if ! printf '%s' "$COMMAND" | command grep -qE "$GH_MERGE_RE"; then
  # Not a gh pr merge call — allow through
  exit 0
fi

# ---------------------------------------------------------------------------
# Extract the PR number from the `gh pr merge` invocation.
#
# Supported forms:
#   gh pr merge 5
#   gh pr merge --squash 5
#   gh pr merge 5 --squash
#   gh pr merge 5 --squash --delete-branch
#   gh pr merge '5'              (single-quoted — strip quotes)
#   gh pr merge "5"              (double-quoted — strip quotes)
#   gh pr merge https://github.com/owner/repo/pull/5  (URL — extract trailing digits)
#   cd /tmp && gh pr merge 5    (compound command — grep finds the merge segment)
#
# Algorithm:
#   1. Extract the segment containing `gh pr merge` (handles compound commands).
#   2. Strip everything up to and including `merge`.
#   3. Walk remaining tokens (split on whitespace):
#      a. Skip flag tokens (start with `-`).
#      b. For the first non-flag token:
#         - If it looks like a URL (contains "pull/"), extract the trailing digits.
#         - If it's a bare integer (possibly quoted), strip quotes and use it.
#         - Otherwise, it's unrecognised — fail open (allow) and warn.
# ---------------------------------------------------------------------------

# Step 1: isolate the gh pr merge segment from a compound command.
# grep -oE extracts the matching portion; head -1 takes the first match.
MERGE_SEGMENT="$(printf '%s' "$COMMAND" | command grep -oE 'gh[[:space:]]+pr[[:space:]]+merge([[:space:]].*)?$' | head -1)"

if [[ -z "$MERGE_SEGMENT" ]]; then
  # Couldn't isolate segment — fail open
  exit 0
fi

# Step 2: strip everything up to and including "merge "
AFTER_MERGE="${MERGE_SEGMENT#*merge}"
# Remove leading whitespace
AFTER_MERGE="${AFTER_MERGE#"${AFTER_MERGE%%[! ]*}"}"

# Step 3: walk tokens to find the PR number
PR_NUM=""
for token in $AFTER_MERGE; do
  # Skip flag arguments (--squash, --delete-branch, -m, etc.)
  if [[ "$token" == -* ]]; then
    continue
  fi

  # Strip surrounding shell quotes (same technique as hook 1 / PR #17 commit 81d300d)
  # Example: "'5'" → "5";  '"42"' → "42"
  if [[ ( "$token" == \'*\' ) || ( "$token" == \"*\" ) ]]; then
    token="${token:1:${#token}-2}"
  fi

  # URL form: https://github.com/owner/repo/pull/5 — extract trailing integer
  if printf '%s' "$token" | command grep -qE 'pull/[0-9]+'; then
    PR_NUM="$(printf '%s' "$token" | command grep -oE 'pull/[0-9]+' | command grep -oE '[0-9]+$')"
    break
  fi

  # Bare integer
  if printf '%s' "$token" | command grep -qE '^[0-9]+$'; then
    PR_NUM="$token"
    break
  fi

  # First non-flag, non-numeric token — could be a branch name or "HEAD".
  # gh pr merge also accepts a branch name or "HEAD" to identify the PR.
  # We can't look up labels without a PR number or URL, so fail open and warn.
  echo "[pr-merge-requires-in-review] WARNING: Could not extract a numeric PR number from: $MERGE_SEGMENT" >&2
  echo "[pr-merge-requires-in-review] Allowing through — verify the PR carries the in-review label manually." >&2
  exit 0
done

if [[ -z "$PR_NUM" ]]; then
  # No number found (e.g., bare `gh pr merge` with no args) — allow through
  exit 0
fi

# ---------------------------------------------------------------------------
# Query the PR's labels.
#
# In --self-test mode CLAUDE_HOOK_GH_LABELS_CMD is set to "mock_label_cmd",
# which is a bash function exported into the environment. In normal mode it is
# unset and we call `gh pr view` directly.
# ---------------------------------------------------------------------------
fetch_labels() {
  local pr_num="$1"
  if [[ -n "${CLAUDE_HOOK_GH_LABELS_CMD:-}" ]]; then
    # Self-test mock: call the stub function/command with the PR number
    bash -c "${CLAUDE_HOOK_GH_LABELS_CMD} ${pr_num}"
  else
    gh pr view "$pr_num" --json labels --jq '[.labels[].name]' 2>/dev/null || echo "[]"
  fi
}

LABELS_JSON="$(fetch_labels "$PR_NUM")"

# Check if `in-review` is present in the label list
if printf '%s' "$LABELS_JSON" | jq -e 'map(select(. == "in-review")) | length > 0' >/dev/null 2>&1; then
  # in-review found — allow
  exit 0
fi

# ---------------------------------------------------------------------------
# BLOCKED — emit a clear error message
# ---------------------------------------------------------------------------
cat >&2 <<EOF
[HOOK BLOCKED] \`gh pr merge ${PR_NUM}\` was intercepted: the PR does not carry the \`in-review\` label.

  Rule: SDLC.md Step 5 — "Apply in-review label (your signal; Code Reviewer
        watches for it). … Code Reviewer merges. Always."

  PR #${PR_NUM} current labels: ${LABELS_JSON}

  Required steps before merging:
    1. Ensure your PR is ready for review (all commits pushed, CI green).
    2. Apply the \`in-review\` label:
         gh pr edit ${PR_NUM} --add-label in-review
    3. Notify or wait for the Code Reviewer to review and merge.
    4. Do NOT merge your own PR.

  Label ownership reference: .claude/skills/label-discipline/

  Override (ops emergency only): set CLAUDE_HOOK_BYPASS=1 in your shell,
  then restart Claude Code. Document the bypass reason in your PR body.
EOF
exit 2
