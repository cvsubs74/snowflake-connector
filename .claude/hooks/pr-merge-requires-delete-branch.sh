#!/usr/bin/env bash
# pr-merge-requires-delete-branch.sh — Hook 6 of 12
#
# PreToolUse / Bash hook: block `gh pr merge <N>` when --delete-branch
# (or -d) is missing from the command. Enforces SDLC.md Step 5's
# branch-deletion convention at command time.
#
# Why both this hook AND a GitHub repo setting?
#   - Server-side: `gh api -X PATCH repos/{owner}/{repo} -f delete_branch_on_merge=true`
#     deletes the remote branch automatically. Catches everything but is
#     invisible to the agent — silent fix, no learning.
#   - This hook: catches the missing flag at command time, prints an
#     actionable message naming the convention, and ensures `gh pr merge`
#     also cleans up the local tracking ref (which the server setting
#     can't do).
#
# Claude Code invokes this script for every Bash tool call. Stdin shape:
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
# Tests live in tests/test_hooks.sh (run via bash tests/run.sh).
#
# Operator override: set CLAUDE_HOOK_BYPASS=1 to skip all checks.
# See .claude/hooks/README.md for full escape-hatch documentation.

set -euo pipefail

# --- Bypass for ops emergencies ---
if [[ "${CLAUDE_HOOK_BYPASS:-}" == "1" ]]; then
  exit 0
fi

# --- Read stdin ---
INPUT="$(cat)"

# Require jq; fail open (allow) if unavailable so the hook is never itself the blocker
if ! command -v jq &>/dev/null; then
  echo "[pr-merge-requires-delete-branch] WARNING: jq not found — hook skipped. Install jq to enable protection." >&2
  exit 0
fi

COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')"

# If we couldn't parse a command, allow through (don't break unrelated tool calls)
if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Detection: does this command contain the adjacent token sequence `gh pr merge`
# as an actual command invocation (not inside a quoted argument)?
#
# The regex requires the three tokens to appear:
#   - at the start of the full command string, OR
#   - after a shell separator (;  &&  ||  |)
# …with only optional whitespace before `gh`.
#
# This prevents false positives from commands like:
#   grep "gh pr merge" SDLC.md          ← 'gh pr merge' is an argument, not a cmd
#   echo "use gh pr merge --delete-branch"  ← same
# while still matching:
#   gh pr merge 5                        ← direct invocation
#   cd /tmp && gh pr merge 5             ← segment after &&
# ---------------------------------------------------------------------------
GH_MERGE_RE='(^|;|&&|\|\||[|])[[:space:]]*gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)'
if ! printf '%s' "$COMMAND" | command grep -qE "$GH_MERGE_RE"; then
  # Not a gh-pr-merge call — allow through
  exit 0
fi

# Isolate the segment starting at the adjacent `gh pr merge` for token walking.
MERGE_SEGMENT="$(printf '%s' "$COMMAND" | command grep -oE 'gh[[:space:]]+pr[[:space:]]+merge([[:space:]].*)?$' | head -1)"

if [[ -z "$MERGE_SEGMENT" ]]; then
  # Couldn't isolate segment — fail open
  exit 0
fi

# ---------------------------------------------------------------------------
# Walk tokens to check for --delete-branch or -d.
# Both are accepted forms per `gh pr merge --help`.
# Quoted tokens are stripped of surrounding quotes (same technique as Hook 1).
# ---------------------------------------------------------------------------
HAS_DELETE_BRANCH=0
for token in $MERGE_SEGMENT; do
  # Strip surrounding shell quotes ('--delete-branch' or "--delete-branch")
  if [[ ( "$token" == \'*\' ) || ( "$token" == \"*\" ) ]]; then
    token="${token:1:${#token}-2}"
  fi

  if [[ "$token" == "--delete-branch" || "$token" == "-d" ]]; then
    HAS_DELETE_BRANCH=1
    break
  fi
done

if [[ "$HAS_DELETE_BRANCH" -eq 1 ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# BLOCKED — emit a clear error message
# ---------------------------------------------------------------------------
cat >&2 <<'EOF'
[HOOK BLOCKED] `gh pr merge` is missing the `--delete-branch` flag.

  Rule: SDLC.md Step 5 — "branches are deleted on merge to keep `origin`
        clean." The repo setting `delete_branch_on_merge=true` cleans the
        remote branch server-side, but this hook enforces the flag at
        command time so:
          1. Local tracking refs are also cleaned (gh pr merge --delete-branch
             removes both local and remote).
          2. Intent is explicit in the command history.

  Required form:
    gh pr merge <N> --squash --delete-branch
  (or the short form: -d in place of --delete-branch)

  Override (ops emergency only): set CLAUDE_HOOK_BYPASS=1 in your shell,
  then restart Claude Code. Document the bypass reason in your PR body.
EOF
exit 2
