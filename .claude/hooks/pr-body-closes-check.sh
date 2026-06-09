#!/usr/bin/env bash
# pr-body-closes-check.sh — Hook 5 of 12
#
# PreToolUse / Bash hook: warn when `gh pr create` is called without a
# GitHub auto-close keyword (Closes/Close/Fix/Fixes/Resolve/Resolves #N)
# in the PR body.
#
# This hook WARNS but NEVER BLOCKS (exit 0 in all non-error paths).
# Some PRs (refactors, chores) legitimately have no tracking issue;
# the warning makes the omission intentional rather than accidental.
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
#   0  — allow (always; warning may be printed to stderr)
#
# Body extraction strategy (in order):
#   1. --body-file <path>                        → read file (if exists + readable) and check
#   2. --body "<text>" or --body '<text>'        → extract inline and check
#   3. Neither present                           → interactive edit; allow (can't check)
#
# NOTE: --body-file is checked BEFORE --body because --body-file contains the
# substring "--body", which would otherwise trip the --body pattern.
#
# NOTE: Body text may contain literal \n sequences (backslash + n) that represent
# newlines when rendered — these are normalised before keyword matching.
#
# Tests live in tests/test_hooks.sh (run via bash tests/run.sh).
#
# Operator override: set CLAUDE_HOOK_BYPASS=1 to skip all checks.
# Rationale: dev-agent.md §5 — "'Closes #N' is mandatory for any PR that
# fully resolves a tracking issue."

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

# Require jq; fail open (allow) if unavailable
if ! command -v jq &>/dev/null; then
  echo "[pr-body-closes-check] WARNING: jq not found — hook skipped. Install jq to enable protection." >&2
  exit 0
fi

COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')"

# If we couldn't parse a command, allow through
if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# --- Only intercept gh pr create ---
if ! printf '%s' "$COMMAND" | command grep -qE '\bgh\b.*\bpr\b.*\bcreate\b'; then
  exit 0
fi

# ---------------------------------------------------------------------------
# warn_missing_closes — emit the warning message to stderr, exit 0
# ---------------------------------------------------------------------------
warn_missing_closes() {
  cat >&2 <<'EOF'
[HOOK WARNING] PR body lacks 'Closes #N' (or equivalent). Issue won't auto-close on merge. See dev-agent.md §5.

  GitHub auto-close keywords accepted:
    Closes #N  |  Close #N  |  Fix #N  |  Fixes #N  |  Resolve #N  |  Resolves #N

  If this PR fully resolves a tracking issue, add one of the above to the body.
  If this is an intentional chore/refactor with no tracking issue, ignore this warning.

  Override: set CLAUDE_HOOK_BYPASS=1 to suppress this warning for the session.
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# has_auto_close_keyword <body>
#   Returns 0 if body contains a GitHub auto-close keyword + issue number.
#   Case-insensitive. Accepts: close, closes, fix, fixes, resolve, resolves
#   followed by optional whitespace and #<one-or-more-digits>.
#
#   The body may contain literal \n sequences (backslash + n) that represent
#   newlines — these are normalised via sed before matching so that keywords
#   at the start of a "line" are not obscured by the preceding word character.
# ---------------------------------------------------------------------------
has_auto_close_keyword() {
  local body="$1"
  # Normalise literal \n → real newline so keyword at line start is not glued
  # to the preceding "n" character from the escape sequence.
  printf '%s' "$body" \
    | command sed 's/\\n/\n/g' \
    | command grep -qiE '(close|closes|fix|fixes|resolve|resolves)[[:space:]]+#[0-9]+'
}

# ---------------------------------------------------------------------------
# IMPORTANT: check --body-file BEFORE --body.
# "--body-file" contains the substring "--body", so a naive --body\b pattern
# would also match --body-file lines. We handle --body-file first and then
# fall through to the --body check only when --body-file is absent.
# ---------------------------------------------------------------------------

# Case 1: --body-file flag present — read the file and check
if printf '%s' "$COMMAND" | command grep -qE -- '--body-file[[:space:]]'; then
  FILE_PATH=""

  # Double-quoted path: --body-file "..."
  if printf '%s' "$COMMAND" | command grep -qE -- '--body-file[[:space:]]+"'; then
    FILE_PATH="$(printf '%s' "$COMMAND" | command sed -E 's/.*--body-file[[:space:]]+"([^"]*)".*/\1/')"

  # Single-quoted path: --body-file '...'
  elif printf '%s' "$COMMAND" | command grep -qE -- "--body-file[[:space:]]+'"; then
    FILE_PATH="$(printf '%s' "$COMMAND" | command sed -E "s/.*--body-file[[:space:]]+'([^']*)'.*/\1/")"

  # Unquoted path: --body-file /some/path
  else
    FILE_PATH="$(printf '%s' "$COMMAND" | command sed -E 's/.*--body-file[[:space:]]+([^[:space:]]+).*/\1/')"
  fi

  if [[ -n "$FILE_PATH" ]]; then
    if [[ -f "$FILE_PATH" && -r "$FILE_PATH" ]]; then
      FILE_BODY="$(cat "$FILE_PATH")"
      if has_auto_close_keyword "$FILE_BODY"; then
        exit 0
      else
        warn_missing_closes
      fi
    else
      # File doesn't exist or isn't readable — can't check; allow through
      exit 0
    fi
  fi
  # Could not parse the file path — allow through
  exit 0
fi

# Case 2: --body flag present (and --body-file is NOT present, checked above)
# Use a pattern that does NOT match --body-file: require that --body is not
# immediately followed by "-file" (but the grep above already confirmed
# --body-file is absent, so a simple --body match is safe here).
if printf '%s' "$COMMAND" | command grep -qE -- '--body[[:space:]]'; then
  BODY=""

  # Double-quoted value: --body "..."
  if printf '%s' "$COMMAND" | command grep -qE -- '--body[[:space:]]+"'; then
    BODY="$(printf '%s' "$COMMAND" | command sed -E 's/.*--body[[:space:]]+"([^"]*)".*/\1/')"

  # Single-quoted value: --body '...'
  elif printf '%s' "$COMMAND" | command grep -qE -- "--body[[:space:]]+'"; then
    BODY="$(printf '%s' "$COMMAND" | command sed -E "s/.*--body[[:space:]]+'([^']*)'.*/\1/")"

  # Unquoted value: --body someword
  else
    BODY="$(printf '%s' "$COMMAND" | command sed -E 's/.*--body[[:space:]]+([^[:space:]]+).*/\1/')"
  fi

  if [[ -n "$BODY" ]]; then
    if has_auto_close_keyword "$BODY"; then
      exit 0
    else
      warn_missing_closes
    fi
  fi
  # --body present but we couldn't extract a value — warn
  warn_missing_closes
fi

# Case 3: Neither --body-file nor --body — interactive edit; allow without warning
exit 0
