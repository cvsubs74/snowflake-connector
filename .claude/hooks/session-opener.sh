#!/usr/bin/env bash
# session-opener.sh — Hook 11 of 12
#
# SessionStart hook: emit the 3-step session opener prompt for the agent.
# Per "Effective harnesses for long-running agents" (Anthropic, Nov 2025):
# coding-agent session opener = (1) read git log + progress file,
# (2) `pwd`, (3) execute init.sh and run end-to-end smoke.
#
# This hook is COMPLEMENTARY to session-start-doc-check.sh:
#   - session-start-doc-check.sh — sanity-checks required cold-start docs exist.
#   - session-opener.sh (this)    — nudges the agent to actually READ memory/.
#
# Behavior:
#   - Always non-blocking (exit 0).
#   - On every session start, emit an [HOOK INFO] block reminding the agent
#     to read memory/PROGRESS.md + memory/DECISIONS.md + the relevant
#     playbook before acting.
#   - If `bin/init.sh` exists, suggest running it.
#
# Operator override: set CLAUDE_HOOK_BYPASS=1 to skip.

set -euo pipefail

if [[ "${CLAUDE_HOOK_BYPASS:-}" == "1" ]]; then
  exit 0
fi

INPUT="$(cat)"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"

# Build the opener message.
HAS_MEMORY=0
HAS_INIT=0
[[ -d "$REPO_ROOT/memory" ]] && HAS_MEMORY=1
[[ -x "$REPO_ROOT/bin/init.sh" ]] && HAS_INIT=1

# Get current branch + recent commits for situational awareness.
BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")"
RECENT="$(git -C "$REPO_ROOT" log --oneline -5 2>/dev/null || echo "(no git history)")"

cat >&2 <<EOF
[HOOK INFO] session-opener: 3-step session opener — read durable state before acting.

  Current branch: ${BRANCH}
  Recent commits:
$(printf '%s\n' "$RECENT" | sed 's/^/    /')

  Step 1 — Read durable state:
EOF

if [[ "$HAS_MEMORY" -eq 1 ]]; then
  cat >&2 <<EOF
    Read memory/PROGRESS.md  (active goals)
    Read memory/DECISIONS.md (architectural choices)
    Read memory/NOTES.md     (exploration notes — prune stale ones)
EOF
else
  cat >&2 <<EOF
    [INFO] memory/ directory not present in this repo.
           If you're using the claude-workflow template, create it via
           bin/init-project.sh, or by copying memory/ from the template.
EOF
fi

cat >&2 <<EOF

  Step 2 — Confirm location:
    pwd                       (you should be in the project root or a worktree)

  Step 3 — Smoke test (only if a long-running app):
EOF

if [[ "$HAS_INIT" -eq 1 ]]; then
  echo "    bash bin/init.sh           (boots dev server + runs end-to-end smoke)" >&2
else
  echo "    [INFO] bin/init.sh not present — skip step 3 for this project." >&2
fi

cat >&2 <<EOF

  Skip steps you've already done in a recent prior turn. The point is to
  ground yourself in durable state, not to repeat work.

  Bypass: set CLAUDE_HOOK_BYPASS=1.
EOF

exit 0
