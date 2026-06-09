#!/usr/bin/env bash
# system-prompt-audit.sh — Hook 9 of 12
#
# PostToolUse / Edit|Write hook: append an audit-log entry whenever a file
# under .claude/agents/, .claude/skills/, or .claude/commands/ is changed.
# Per the Apr 23 postmortem: prompt-line changes had outsized quality impact;
# audit trail + one-command revert is the defense.
#
# Behavior:
#   - On edit to .claude/agents/*.md, .claude/skills/*/SKILL.md,
#     .claude/commands/*.md: append a line to .claude/audit/system-prompt-changes.log
#     with timestamp, file, session-id (if available), and diff stat.
#   - Non-blocking. Exit 0 always.
#
# The audit log is the source of truth for "when did this prompt change?"
# Pair with `git log -p <file>` for the actual diff.
#
# Operator override: set CLAUDE_HOOK_BYPASS=1 to skip.

set -euo pipefail

if [[ "${CLAUDE_HOOK_BYPASS:-}" == "1" ]]; then
  exit 0
fi

INPUT="$(cat)"

if ! command -v jq &>/dev/null; then
  exit 0
fi

TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')"
case "$TOOL" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')"
[[ -z "$FILE_PATH" ]] && exit 0

# Only audit changes under the system-prompt surface.
case "$FILE_PATH" in
  *.claude/agents/*|*.claude/skills/*/SKILL.md|*.claude/commands/*) ;;
  *) exit 0 ;;
esac

# Get session id if available (for cross-referencing).
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // ""')"

# Get the diff stat for the change.
DIFF_STAT=""
if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  DIFF_STAT="$(git diff --shortstat -- "$FILE_PATH" 2>/dev/null || true)"
  [[ -z "$DIFF_STAT" ]] && DIFF_STAT="$(git diff --cached --shortstat -- "$FILE_PATH" 2>/dev/null || true)"
fi

# Find audit dir relative to repo root.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
AUDIT_DIR="$REPO_ROOT/.claude/audit"
AUDIT_LOG="$AUDIT_DIR/system-prompt-changes.log"

mkdir -p "$AUDIT_DIR"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s\tsession=%s\tfile=%s\tdiff=%s\n' "$TS" "${SESSION_ID:-unknown}" "$FILE_PATH" "${DIFF_STAT:-no-diff}" >> "$AUDIT_LOG"

echo "[HOOK INFO] system-prompt-audit: logged change to ${FILE_PATH}. See .claude/audit/system-prompt-changes.log." >&2

exit 0
