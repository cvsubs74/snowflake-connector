#!/usr/bin/env bash
# restricted-label-ownership.sh — Hook 2 of 12
#
# PreToolUse / Bash hook: enforce label ownership rules per label-discipline.
#
# Claude Code invokes this script for every Bash tool call. It receives a JSON
# object on stdin with the following shape (as of Claude Code hooks contract):
#
#   {
#     "tool_name": "Bash",
#     "tool_input": {
#       "command": "<the bash command string>"
#     },
#     "agent_type": "<agent-name>",   // present only in subagent context
#     ...
#   }
#
# The hook intercepts:
#   gh issue edit ... --add-label <X>
#   gh issue edit ... --remove-label <X>
#   gh pr edit     ... --add-label <X>
#   gh pr edit     ... --remove-label <X>
#
# Restricted-label ownership table (per label-discipline SKILL.md):
#   prioritized, priority:high, priority:medium, priority:low  → pm-agent
#   resolved                                                   → qa-agent
#   in-review                                                  → dev-agent only
#   pm                                                         → pm-agent
#   qa                                                         → qa-agent
#
# Agent identity is read from the "agent_type" field in stdin JSON, which Claude
# Code sets when running inside a subagent context (--agent flag or sub-agent
# spawn). When agent_type is absent (operator direct session), the hook FAILS
# OPEN (allows) and emits a stderr WARNING — it cannot enforce ownership without
# identity. See README.md "Limitation: agent identity" for follow-up issue.
#
# NOTE: Written for bash 3.2 compatibility (macOS ships bash 3.2). No declare -A.
#
# Exit codes:
#   0  — allow (silent, or with WARNING to stderr)
#   2  — block (Claude Code surfaces stderr to the user)
#
# Smoke-test examples:
#   Block (dev adds prioritized):
#     echo '{"tool_name":"Bash","tool_input":{"command":"gh issue edit 5 --add-label prioritized"},"agent_type":"dev-agent"}' \
#       | bash restricted-label-ownership.sh
#
#   Allow (pm adds prioritized):
#     echo '{"tool_name":"Bash","tool_input":{"command":"gh issue edit 5 --add-label prioritized"},"agent_type":"pm-agent"}' \
#       | bash restricted-label-ownership.sh
#
#   Allow (no agent context — fail open with WARNING):
#     echo '{"tool_name":"Bash","tool_input":{"command":"gh issue edit 5 --add-label prioritized"}}' \
#       | bash restricted-label-ownership.sh
#
# Tests live in tests/test_hooks.sh (run via bash tests/run.sh).
#
# Operator override: set CLAUDE_HOOK_BYPASS=1 to skip all checks.
# See .claude/hooks/README.md for full escape-hatch documentation.

set -euo pipefail

# ---------------------------------------------------------------------------
# Label ownership lookup (bash 3.2 compatible — no declare -A)
#
# get_label_owners <label>
#   Prints the space-separated list of authorised agent_type values for a
#   restricted label, or an empty string if the label is unrestricted.
# ---------------------------------------------------------------------------
get_label_owners() {
  local lbl="$1"
  case "$lbl" in
    prioritized)      printf '%s' "pm-agent" ;;
    priority:high)    printf '%s' "pm-agent" ;;
    priority:medium)  printf '%s' "pm-agent" ;;
    priority:low)     printf '%s' "pm-agent" ;;
    pm)               printf '%s' "pm-agent" ;;
    resolved)         printf '%s' "qa-agent" ;;
    qa)               printf '%s' "qa-agent" ;;
    in-review)        printf '%s' "dev-agent" ;;
    *)                printf '%s' "" ;;
  esac
}


# ---------------------------------------------------------------------------
# Normal hook mode
# ---------------------------------------------------------------------------

# --- Bypass for ops emergencies ---
if [[ "${CLAUDE_HOOK_BYPASS:-}" == "1" ]]; then
  exit 0
fi

# --- Read stdin ---
INPUT="$(cat)"

# Require jq; fail open if unavailable so the hook is never itself the blocker
if ! command -v jq &>/dev/null; then
  echo "[restricted-label-ownership] WARNING: jq not found — hook skipped. Install jq to enable protection." >&2
  exit 0
fi

COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')"

# If we couldn't parse a command, allow through (don't break unrelated tool calls)
if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# Only care about gh issue/pr edit commands
if ! printf '%s' "$COMMAND" | command grep -qE '\bgh\b.*(issue|pr)\s+edit\b'; then
  exit 0
fi

# Only care if --add-label or --remove-label is present
if ! printf '%s' "$COMMAND" | command grep -qE '\-\-(add|remove)-label\b'; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Agent identity
# Claude Code sets "agent_type" in stdin JSON when running in subagent context.
# If absent, we cannot enforce ownership — fail open with a WARNING.
# ---------------------------------------------------------------------------
AGENT_TYPE="$(printf '%s' "$INPUT" | jq -r '.agent_type // ""')"

# ---------------------------------------------------------------------------
# Extract all labels from --add-label and --remove-label flags.
# gh CLI accepts these forms:
#   --add-label foo
#   --add-label "foo,bar"
#   --add-label foo --add-label bar
#   --remove-label foo
# We extract each value that follows --add-label or --remove-label.
# ---------------------------------------------------------------------------
extract_labels() {
  local cmd="$1"
  # Match --add-label or --remove-label followed by a value (possibly quoted)
  # Use grep -oE to extract each value; strip surrounding quotes; split on comma
  # Use sed -E for extended regex (required on macOS/BSD sed)
  printf '%s' "$cmd" | \
    command grep -oE '\-\-(add|remove)-label[= ][^[:space:]]+' | \
    sed -E 's/--(add|remove)-label[= ]//; s/^["'"'"']//; s/["'"'"']$//' | \
    tr ',' '\n'
}

# ---------------------------------------------------------------------------
# is_authorised <agent_type> <owners_str>
#   Returns 0 if agent_type matches any word in owners_str (space-separated).
# ---------------------------------------------------------------------------
is_authorised() {
  local agent="$1"
  local owners="$2"
  local owner
  for owner in $owners; do
    if [[ "$agent" == "$owner" ]]; then
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Iterate over labels in the command and enforce ownership
# ---------------------------------------------------------------------------
while IFS= read -r lbl; do
  lbl="$(printf '%s' "$lbl" | tr -d '[:space:]')"
  [[ -z "$lbl" ]] && continue

  owners="$(get_label_owners "$lbl")"

  # Unrestricted label — anyone may apply
  if [[ -z "$owners" ]]; then
    continue
  fi

  # No agent identity available — fail open with a WARNING
  if [[ -z "$AGENT_TYPE" ]]; then
    cat >&2 <<EOF
[restricted-label-ownership] WARNING: Cannot determine calling agent identity \
(agent_type not set in hook stdin). Allowing label '${lbl}' through without ownership check.
This is expected for operator direct sessions. See .claude/hooks/README.md §Limitation.
EOF
    # Continue checking remaining labels (they'll all fail-open too)
    continue
  fi

  if ! is_authorised "$AGENT_TYPE" "$owners"; then
    cat >&2 <<EOF
[HOOK BLOCKED] Label ownership violation: '${lbl}' is a restricted label.

  Calling agent : ${AGENT_TYPE}
  Authorised    : ${owners}

  Per label-discipline (SKILL.md), only the authorised agent(s) may apply or
  remove '${lbl}'. This rule prevents unilateral privilege escalation
  (e.g., Dev self-promoting a backlog item by applying 'prioritized').

  If you believe this is wrong, options:
    1. Have the authorised agent apply the label directly.
    2. Ask the operator to apply it (operator overrides are always allowed).
    3. Set CLAUDE_HOOK_BYPASS=1 in your shell for an ops-emergency override
       (document the reason in your commit or PR body).

  Reference: .claude/skills/label-discipline/SKILL.md
EOF
    exit 2
  fi

done < <(extract_labels "$COMMAND")

# --- All checks passed ---
exit 0
