#!/usr/bin/env bash
# deploy-reminder.sh — Hook 12 of 12
#
# UserPromptSubmit hook: when the operator's prompt mentions deploy/release/
# prod/ship-to-prod language, inject a reminder about soak periods and
# cohort rollout. Per Apr 23 postmortem: three independent changes degraded
# different traffic slices; aggregate metrics masked it.
#
# Behavior:
#   - Always non-blocking (exit 0).
#   - On deploy-related prompts: emit an [HOOK INFO] reminding the agent to
#     (a) plan a soak period, (b) segment the rollout by cohort, (c) wire
#     prod_monitor before flipping the switch.
#
# Input shape (UserPromptSubmit hook):
#   {
#     "session_id": "<uuid>",
#     "user_prompt": "<the operator's message text>"
#   }
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

PROMPT="$(printf '%s' "$INPUT" | jq -r '.user_prompt // ""')"
[[ -z "$PROMPT" ]] && exit 0

# Triggers — only fire on operator-initiated deploy/release language, not on
# every mention of the word "production".
TRIGGER_RE='(\bdeploy\b|\bpromote to prod\b|\bship to prod\b|\brelease\b|\bcut a release\b|\brollout\b|\bgo live\b)'

if printf '%s' "$PROMPT" | command grep -qiE "$TRIGGER_RE"; then
  cat >&2 <<EOF
[HOOK INFO] deploy-reminder: this prompt mentions deploy / release / rollout.

  Per the Apr 23 postmortem and the Sept 2025 postmortem, defenses to wire
  BEFORE flipping the switch:

  1. **Soak period.** Land the change behind a flag, run for ≥1h on
     internal/canary, watch cohort-segmented metrics. Don't enable for
     real traffic until at least one full diurnal cycle has passed.

  2. **Cohort rollout.** Enable for one segment first (e.g., region.eu-west,
     plan.enterprise, agent.qa). Watch /eval --cohort <segment> output.
     Only widen after that cohort holds for 24h.

  3. **Pre-deploy checks.** Run:
       /eval                                          # full suite
       python evals/prod_monitor/cross_platform_eq.py # AWS/GCP/local
       python evals/prod_monitor/cohort_segment.py    # current baseline

  4. **Rollback rehearsal.** Verify the rollback command works before you
     need it. "git revert" + redeploy should take <5 min.

  5. **Staff cohort.** Make sure internal users get the SAME build as
     external — the Apr 23 cache bug only manifested in stale sessions
     because staff used a different build path.

  Bypass: set CLAUDE_HOOK_BYPASS=1.
EOF
fi

exit 0
