#!/usr/bin/env bash
# verification-gate.sh — Hook 10 of 12
#
# Stop hook: nudge the agent to verify before claiming "done" / "complete" /
# "ready to ship" / "fixed". Per superpowers:verification-before-completion
# and the Apr 23 postmortem: "evidence before assertions, always."
#
# Behavior:
#   - Read transcript_path from stdin.
#   - Scan the last few assistant messages for "done"/"complete"/"fixed"/
#     "ready to ship"/etc. AND for evidence (recent tool calls that ran
#     tests, lint, or verification commands).
#   - If "done" language present but no verification evidence in the same
#     session window: emit [HOOK WARNING] nudging the agent to verify.
#   - Default: NON-BLOCKING (warn only). Set CLAUDE_HOOK_GATE_STOP=block
#     to make it block (exit 2) — useful for CI runs.
#
# Input shape (Stop hook):
#   {
#     "session_id": "<uuid>",
#     "transcript_path": "/path/to/transcript.jsonl"
#   }
#
# Operator override: set CLAUDE_HOOK_BYPASS=1 to skip entirely.

set -euo pipefail

if [[ "${CLAUDE_HOOK_BYPASS:-}" == "1" ]]; then
  exit 0
fi

INPUT="$(cat)"

if ! command -v jq &>/dev/null; then
  exit 0
fi

TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""')"
[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && exit 0

# Pull the last ~20 entries from the JSONL transcript.
TAIL_ENTRIES="$(command tail -n 30 "$TRANSCRIPT" 2>/dev/null || true)"
[[ -z "$TAIL_ENTRIES" ]] && exit 0

# Look for "done" language in recent assistant turns.
DONE_RE='(\bdone\b|\bcomplete[d]?\b|\bfixed\b|\bready to ship\b|\ball tests pass\b|\bworking now\b|\bworks now\b|\bshould work now\b)'
DONE_HITS=$(printf '%s' "$TAIL_ENTRIES" | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' 2>/dev/null | command grep -cEi "$DONE_RE" || true)

# Look for verification evidence in recent tool calls.
VERIFY_RE='(pytest|jest|cargo test|go test|npm test|bash tests/|mocha|rspec|vitest|playwright|lint|tsc|mypy|ruff|eslint|/verify|/eval|/heartbeat)'
VERIFY_HITS=$(printf '%s' "$TAIL_ENTRIES" | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | .input.command? // ""' 2>/dev/null | command grep -cEi "$VERIFY_RE" || true)

# If the agent's about to claim done but didn't verify in this session, warn.
if [[ "$DONE_HITS" -gt 0 && "$VERIFY_HITS" -eq 0 ]]; then
  cat >&2 <<EOF
[HOOK WARNING] verification-gate: assistant is claiming completion but I see
no recent test/lint/verify calls in the transcript.

Per superpowers:verification-before-completion and the Apr 23 postmortem:
evidence before assertions. Before claiming "done" / "fixed" / "complete",
run one of:

  - The test suite (pytest / jest / cargo test / npm test / bash tests/run.sh)
  - The /verify command (Playwright-driven UI check)
  - The /eval command (against your changed cohort)
  - The relevant lint/type-check

If you DID verify in this session, this warning is a false positive — proceed.
If you didn't, please verify and re-state the conclusion based on the result.

This hook is advisory by default. Set CLAUDE_HOOK_GATE_STOP=block to make it
blocking (useful for CI/headless runs).

Bypass: set CLAUDE_HOOK_BYPASS=1.
EOF
  if [[ "${CLAUDE_HOOK_GATE_STOP:-}" == "block" ]]; then
    exit 2
  fi
fi

exit 0
