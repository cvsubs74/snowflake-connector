#!/usr/bin/env bash
# workaround-audit.sh — Hook 8 of 12
#
# PostToolUse / Edit|Write hook: flag added or removed WORKAROUND/HACK/FIXME
# comments. Postmortem-prevention defense (per Sept 2025 postmortem) —
# silently removing a workaround can re-introduce a bug a previous engineer
# walked around.
#
# Behavior:
#   - On NEW comment (Added: # WORKAROUND, # HACK, # FIXME, // WORKAROUND, etc.):
#     emit [HOOK INFO] noting the addition. Non-blocking.
#   - On REMOVED comment (Deleted lines containing such markers):
#     emit [HOOK WARNING] requiring a root-cause note. Still non-blocking
#     (false positives on legitimate refactors are too costly to hard-block),
#     but the warning is loud and asks Claude to add context.
#
# Input shape:
#   {
#     "tool_name": "Edit"|"Write",
#     "tool_input": { "file_path": "..." , ... },
#     "tool_response": { ... }
#   }
#
# Exit code: always 0 (advisory only).
#
# Operator override: set CLAUDE_HOOK_BYPASS=1 to skip.
# Test override: CLAUDE_HOOK_TEST_DIFF=<text> to provide a synthetic diff.

set -euo pipefail

if [[ "${CLAUDE_HOOK_BYPASS:-}" == "1" ]]; then
  exit 0
fi

INPUT="$(cat)"

if ! command -v jq &>/dev/null; then
  exit 0   # fail open
fi

TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')"
case "$TOOL" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')"
[[ -z "$FILE_PATH" ]] && exit 0

# Build the diff to scan. Prefer the actual diff against HEAD; fall back to
# the test override if provided.
DIFF=""
if [[ -n "${CLAUDE_HOOK_TEST_DIFF:-}" ]]; then
  DIFF="$CLAUDE_HOOK_TEST_DIFF"
else
  if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    DIFF="$(git diff --no-color -- "$FILE_PATH" 2>/dev/null || true)"
    if [[ -z "$DIFF" ]]; then
      DIFF="$(git diff --cached --no-color -- "$FILE_PATH" 2>/dev/null || true)"
    fi
  fi
fi

[[ -z "$DIFF" ]] && exit 0

MARKER_RE='(WORKAROUND|HACK|FIXME|XXX|TODO\(claim\))'

# Count added vs removed marker lines.
ADDED_MARKERS=$(printf '%s' "$DIFF" | command grep -cE "^\+[^+].*${MARKER_RE}" || true)
REMOVED_MARKERS=$(printf '%s' "$DIFF" | command grep -cE "^-[^-].*${MARKER_RE}" || true)

if [[ "$REMOVED_MARKERS" -gt 0 ]]; then
  cat >&2 <<EOF
[HOOK WARNING] workaround-audit: ${REMOVED_MARKERS} WORKAROUND/HACK/FIXME comment(s) removed from ${FILE_PATH}.

  Per the Sept 2025 postmortem: silently removing a workaround can re-introduce
  a bug a previous engineer walked around. If you removed one, please:

  1. Add a root-cause note to the commit / PR description.
     Cite the underlying fix that made the workaround unnecessary.
  2. Verify the original symptom doesn't recur — run the eval suite
     that covers this code path (/eval --cohort <area>).

  This is advisory only; the hook does not block. But please don't merge
  the change without the root-cause note.

  Bypass: set CLAUDE_HOOK_BYPASS=1.
EOF
fi

if [[ "$ADDED_MARKERS" -gt 0 ]]; then
  echo "[HOOK INFO] workaround-audit: ${ADDED_MARKERS} new WORKAROUND/HACK/FIXME comment(s) in ${FILE_PATH}. Make sure each one cites the underlying issue + a removal path." >&2
fi

exit 0
