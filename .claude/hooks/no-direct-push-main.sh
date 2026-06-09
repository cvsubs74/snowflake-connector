#!/usr/bin/env bash
# no-direct-push-main.sh — Hook 1 of 12
#
# PreToolUse / Bash hook: block direct git commit/push to main.
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
# Tests live in tests/test_hooks.sh (run via bash tests/run.sh).
#
# Operator override: set CLAUDE_HOOK_BYPASS=1 to skip all checks.
# Protected-branch list: set CLAUDE_HOOK_PROTECTED_BRANCHES="main master develop"
# to override the default ("main master"). Space-separated list of branch names.
# Test-branch override (for tests and CI):
#   CLAUDE_HOOK_TEST_BRANCH=<branch>  use this value instead of git symbolic-ref
#   (makes the commit-guard check hermetic regardless of the real checkout branch)
# See .claude/hooks/README.md for full escape-hatch documentation.

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
  echo "[no-direct-push-main] WARNING: jq not found — hook skipped. Install jq to enable protection." >&2
  exit 0
fi

COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')"

# If we couldn't parse a command, allow through (don't break unrelated tool calls)
if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# --- Protected branch list ---
# Configurable via CLAUDE_HOOK_PROTECTED_BRANCHES (space-separated). Default: main master
PROTECTED_BRANCHES="${CLAUDE_HOOK_PROTECTED_BRANCHES:-main master}"

# ---------------------------------------------------------------------------
# is_protected_ref <ref>
#   Returns 0 if <ref> (after stripping leading + and refs/heads/ prefix)
#   matches any protected branch name.
# ---------------------------------------------------------------------------
is_protected_ref() {
  local ref="$1"
  # Strip leading + (force-push shorthand)
  ref="${ref#\+}"
  # Strip refs/heads/ prefix
  ref="${ref#refs/heads/}"
  local protected
  for protected in $PROTECTED_BRANCHES; do
    if [[ "$ref" == "$protected" ]]; then
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# block_push — emit the block message and exit 2
# ---------------------------------------------------------------------------
block_push() {
  cat >&2 <<'EOF'
[HOOK BLOCKED] Direct push to a protected branch (main/master) is not allowed.

  Rule: SDLC.md Step 2 — "No direct commits to the default branch.
        Every change goes through a PR."

  Blocked forms include:
    git push origin main
    git push origin HEAD:main          (refspec)
    git push origin refs/heads/main    (full refname)
    git push origin main:main          (local:remote refspec)
    git push origin +main              (force shorthand)
    git push origin :main              (delete remote branch)

  Required workflow:
    1. Create a feature branch: git checkout -b feat/<issue>-<slug>
    2. Push the branch:         git push origin feat/<issue>-<slug>
    3. Open a PR on GitHub.

  Override (ops emergency only): set CLAUDE_HOOK_BYPASS=1 in your shell,
  then restart Claude Code. Document the bypass reason in your commit or PR.
EOF
  exit 2
}

# --- Check 1: git push to a protected remote branch ---
#
# Strategy:
#   1. Detect "git push" anywhere in the command.
#   2. Tokenise the argument list (words after "push").
#   3. Skip flag tokens (start with -) and the remote token (first non-flag word).
#      Everything else is a refspec.
#   4. For each refspec:
#      - Strip leading + (force shorthand)
#      - If it contains ':', the remote-side ref is the part after ':'.
#        Otherwise the whole token is both local and remote side.
#      - Strip refs/heads/ prefix from the remote side.
#      - If that ref matches a protected branch → block.
#   5. No refspec tokens at all means "git push <remote>" — the remote ref
#      defaults to the local branch name, which the hook does NOT know from
#      the command string alone (would need 'git rev-parse'). We conservatively
#      allow this form and rely on Check 2 (commit guard) to catch the main case.
#      In practice, "git push origin" without a refspec is rarely dangerous
#      because the CI hooks in origin block non-PR pushes.

if printf '%s' "$COMMAND" | command grep -qE '\bgit\b.*\bpush\b'; then
  # Extract the portion of the command starting from "push" (handle multi-command lines)
  PUSH_ARGS="$(printf '%s' "$COMMAND" | command grep -oE '\bpush\b.*' | head -1)"
  # Remove the word "push" itself
  PUSH_ARGS="${PUSH_ARGS#push}"

  FOUND_REMOTE=0
  FOUND_REFSPEC=0
  for token in $PUSH_ARGS; do
    # Skip flag arguments (--force, -f, -u, --set-upstream, etc.)
    if [[ "$token" == -* ]]; then
      continue
    fi

    # Option A: strip surrounding shell quotes (' or ") from the token before
    # any comparison. The tokenizer (for token in $PUSH_ARGS) splits on
    # whitespace but does NOT strip shell quoting characters, so the five-char
    # string "'origin'" would not match the four-char string "origin". We strip
    # matching pairs of leading/trailing single or double quotes here.
    # Example: "'origin'" → "origin";  '"main"' → "main"
    if [[ ( "$token" == \'*\' ) || ( "$token" == \"*\" ) ]]; then
      token="${token:1:${#token}-2}"
    fi

    # First non-flag word is the remote (e.g. "origin", "upstream")
    if [[ "$FOUND_REMOTE" -eq 0 ]]; then
      FOUND_REMOTE=1
      # We only guard "origin" (or whatever the configured protected remote is).
      # If the remote isn't "origin", let it through — non-goals per issue #9.
      # Accept: origin (exact). Allow others to pass.
      if [[ "$token" != "origin" ]]; then
        break
      fi
      continue
    fi
    # Remaining tokens are refspecs
    FOUND_REFSPEC=1
    local_side="$token"
    remote_side=""

    # Strip leading + before checking for ':'
    stripped="${local_side#\+}"
    if [[ "$stripped" == *:* ]]; then
      # local:remote form — take the part after the last ':'
      remote_side="${stripped##*:}"
    else
      # Simple form — local and remote are the same
      remote_side="$stripped"
    fi

    # Empty remote side = "git push origin :branch" (delete) — still extract the branch
    # Actually for ":main" the stripped is ":main", remote_side after ## is "main"
    # That's handled: stripped=":main", contains ":", remote_side="main"

    if is_protected_ref "$remote_side"; then
      block_push
    fi
  done
fi

# --- Check 2: git commit while on main / master ---
# Determine the current branch from git; if we're not in a git repo, allow through.
# CLAUDE_HOOK_TEST_BRANCH overrides real git state (for hermetic self-tests and CI).
CURRENT_BRANCH=""
if [[ -n "${CLAUDE_HOOK_TEST_BRANCH:-}" ]]; then
  CURRENT_BRANCH="$CLAUDE_HOOK_TEST_BRANCH"
elif git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo "")"
fi

if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
  if printf '%s' "$COMMAND" | command grep -qE '^\s*git\s+commit\b'; then
    cat >&2 <<'EOF'
[HOOK BLOCKED] Direct commit to main/master is not allowed.

  Rule: SDLC.md Step 2 — "No direct commits to the default branch.
        Every change goes through a PR."

  You are currently on branch: main (or master)

  Required workflow:
    1. Create a feature branch: git checkout -b feat/<issue>-<slug>
    2. Make your commits there.
    3. Push + open a PR on GitHub.

  Operator emergency override: set CLAUDE_HOOK_BYPASS=1 in your shell,
  then restart Claude Code. Document the bypass reason in your commit or PR.
EOF
    exit 2
  fi
fi

# --- All checks passed ---
exit 0
