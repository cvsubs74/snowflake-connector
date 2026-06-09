#!/usr/bin/env bash
# tests/lib.sh — shared assertion helpers for hook tests.
#
# Reused verbatim from .claude/hooks/no-direct-push-main.sh lines 44-72
# (the canonical run_case pattern). One sourcing per test_*.sh file.
#
# Counters PASS / FAIL are file-scoped; each test file calls print_summary
# at the end and exits with its status.

# Note: do NOT `set -e` here — tests must capture failures and keep going.
set -uo pipefail

PASS=${PASS:-0}
FAIL=${FAIL:-0}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.claude/hooks"

# ---------------------------------------------------------------------------
# emit_payload <cmd> [agent_type]
# Builds the JSON payload for a hook's stdin. If agent_type is provided,
# adds it as a top-level field (used by Hook 2).
# ---------------------------------------------------------------------------
emit_payload() {
  local cmd="$1"
  local agent="${2:-}"
  if [[ -n "$agent" ]]; then
    jq -cn --arg cmd "$cmd" --arg agent "$agent" \
      '{"tool_name":"Bash","tool_input":{"command":$cmd},"agent_type":$agent}'
  else
    jq -cn --arg cmd "$cmd" \
      '{"tool_name":"Bash","tool_input":{"command":$cmd}}'
  fi
}

# ---------------------------------------------------------------------------
# run_case <hook_script> <label> <cmd> <expect> [agent_type]
# Runs the hook against a payload built from <cmd>; checks exit code.
# expect: "block" (exit 2) or "allow" (exit 0).
# Used by Hooks 1, 2, 3, 6.
# ---------------------------------------------------------------------------
run_case() {
  local hook="$1"
  local label="$2"
  local cmd="$3"
  local expect="$4"
  local agent="${5:-}"

  local payload
  payload="$(emit_payload "$cmd" "$agent")"

  local exit_code=0
  printf '%s' "$payload" | bash "$hook" >/dev/null 2>&1 || exit_code=$?

  local actual
  if [[ "$exit_code" -eq 2 ]]; then actual="block"; else actual="allow"; fi

  if [[ "$actual" == "$expect" ]]; then
    printf '  PASS  %-62s  (%s)\n' "$label" "$expect"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  %-62s  expected=%s actual=%s\n' "$label" "$expect" "$actual"
    FAIL=$(( FAIL + 1 ))
  fi
}

# ---------------------------------------------------------------------------
# run_case_warn <hook_script> <label> <cmd> <expect>
# For warn-but-don't-block hooks (Hook 5). Detection: stderr contains
# "[HOOK WARNING]" → warn; otherwise → allow. Exit code is ignored
# because warn-style hooks always exit 0.
# ---------------------------------------------------------------------------
run_case_warn() {
  local hook="$1"
  local label="$2"
  local cmd="$3"
  local expect="$4"

  local payload
  payload="$(emit_payload "$cmd")"

  local stderr_out
  stderr_out="$(printf '%s' "$payload" | bash "$hook" 2>&1 >/dev/null || true)"

  local actual
  if printf '%s' "$stderr_out" | command grep -q "\[HOOK WARNING\]"; then
    actual="warn"
  else
    actual="allow"
  fi

  if [[ "$actual" == "$expect" ]]; then
    printf '  PASS  %-62s  (%s)\n' "$label" "$expect"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  %-62s  expected=%s actual=%s\n' "$label" "$expect" "$actual"
    FAIL=$(( FAIL + 1 ))
  fi
}

# ---------------------------------------------------------------------------
# assert_eq <label> <actual> <expected>
# Generic equality check for consistency / structure tests.
# ---------------------------------------------------------------------------
assert_eq() {
  local label="$1"
  local actual="$2"
  local expected="$3"

  if [[ "$actual" == "$expected" ]]; then
    printf '  PASS  %s\n' "$label"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  %s\n' "$label"
    printf '        expected: %s\n' "$expected"
    printf '        actual:   %s\n' "$actual"
    FAIL=$(( FAIL + 1 ))
  fi
}

# ---------------------------------------------------------------------------
# assert_set_eq <label> <set_a_newline_separated> <set_b_newline_separated>
# Set-equality check via sort+diff. Whitespace-tolerant.
# Prints the diff on failure.
# ---------------------------------------------------------------------------
assert_set_eq() {
  local label="$1"
  local a
  local b
  a="$(printf '%s\n' "$2" | sed '/^$/d' | sort -u)"
  b="$(printf '%s\n' "$3" | sed '/^$/d' | sort -u)"

  if [[ "$a" == "$b" ]]; then
    printf '  PASS  %s\n' "$label"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  %s\n' "$label"
    diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") | sed 's/^/        /'
    FAIL=$(( FAIL + 1 ))
  fi
}

# ---------------------------------------------------------------------------
# emit_post_payload <cmd> [tool_stdout] [tool_stderr] [exit_code]
# Builds the PostToolUse JSON payload for Hook 7's stdin.
# Uses the real Claude Code runtime field names (issue #81 fix):
#   tool_response: { "stdout": ..., "stderr": ..., "exit_code": ... }
# Also emits the legacy "output"/"error" fields for backward compat with any
# tests that were written before the field-name correction.
# tool_stdout, tool_stderr, and exit_code default to empty / 0.
# ---------------------------------------------------------------------------
emit_post_payload() {
  local cmd="$1"
  local out="${2:-}"
  local err="${3:-}"
  local exit_code="${4:-0}"
  jq -cn --arg cmd "$cmd" --arg out "$out" --arg err "$err" --argjson ec "$exit_code" \
    '{"tool_name":"Bash","tool_input":{"command":$cmd},"tool_response":{"stdout":$out,"stderr":$err,"exit_code":$ec}}'
}

# ---------------------------------------------------------------------------
# run_case_post <hook_script> <label> <cmd> <expect> [tool_output] [tool_error]
# For PostToolUse hooks that always exit 0.
# expect: "cleanup" (stderr contains "[auto-clean-worktree] Removing") or
#         "warn"    (stderr contains "[auto-clean-worktree] WARNING") or
#         "silent"  (none of the above — hook ran but did nothing).
# ---------------------------------------------------------------------------
run_case_post() {
  local hook="$1"
  local label="$2"
  local cmd="$3"
  local expect="$4"
  local tool_out="${5:-}"
  local tool_err="${6:-}"

  local payload
  payload="$(emit_post_payload "$cmd" "$tool_out" "$tool_err")"

  local stderr_out
  stderr_out="$(printf '%s' "$payload" | bash "$hook" 2>&1 >/dev/null || true)"

  local actual
  if printf '%s' "$stderr_out" | command grep -q "\[auto-clean-worktree\] Removing"; then
    actual="cleanup"
  elif printf '%s' "$stderr_out" | command grep -q "\[auto-clean-worktree\] WARNING"; then
    actual="warn"
  else
    actual="silent"
  fi

  if [[ "$actual" == "$expect" ]]; then
    printf '  PASS  %-62s  (%s)\n' "$label" "$expect"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  %-62s  expected=%s actual=%s\n' "$label" "$expect" "$actual"
    if [[ -n "$stderr_out" ]]; then
      printf '        stderr: %s\n' "$stderr_out"
    fi
    FAIL=$(( FAIL + 1 ))
  fi
}

# ---------------------------------------------------------------------------
# print_summary
# Prints the pass/fail tally; sets the exit code on the caller.
# ---------------------------------------------------------------------------
print_summary() {
  echo ""
  echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
  [[ "$FAIL" -eq 0 ]]
}
