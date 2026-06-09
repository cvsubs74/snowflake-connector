#!/usr/bin/env bash
# ci-status.sh — one-shot snapshot of the last 10 CI workflow runs on main.
# Companion diagnostic to bin/team-status.sh.

set -euo pipefail

# ── helpers ─────────────────────────────────────────────────────────────────

section() {
  echo ""
  echo "── $1 ──────────────────────────────────────────────────────────────"
}

# ── github auth check ────────────────────────────────────────────────────────

GH_OK=0
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    GH_OK=1
  else
    echo "" >&2
    echo "NOTE: gh CLI not authenticated — cannot fetch CI runs." >&2
    echo "      Run \`gh auth login\` to enable full output." >&2
  fi
else
  echo "" >&2
  echo "NOTE: gh CLI not found — cannot fetch CI runs." >&2
fi

if [[ "$GH_OK" -eq 0 ]]; then
  exit 0
fi

# ── §1 workflow runs on main (last 10) ───────────────────────────────────────

section "Workflow runs on origin/main (last 10)"

RUNS_JSON="$(gh run list --branch main --limit 10 \
  --json status,conclusion,name,headSha,createdAt,url 2>/dev/null || echo '[]')"

RUN_COUNT="$(printf '%s' "$RUNS_JSON" | jq 'length')"

if [[ "$RUN_COUNT" -eq 0 ]]; then
  echo "  (no CI runs found)"
  echo ""
  exit 0
fi

# Print each run: icon  conclusion  workflow-name  short-sha  relative-time
printf '%s' "$RUNS_JSON" | jq -r '.[] |
  (.headSha[:7]) as $sha |
  (.createdAt)   as $ts  |
  "\(.status)|\(.conclusion // "—")|\(.name)|\($sha)|\($ts)"' \
| while IFS='|' read -r status conclusion name sha ts; do
    # Compute relative time (seconds since createdAt)
    if date -d "$ts" +%s >/dev/null 2>&1; then
      # GNU date (Linux)
      created_s="$(date -d "$ts" +%s)"
    else
      # BSD date (macOS) — format includes Z to match input character-for-character
      created_s="$(date -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s 2>/dev/null || echo 0)"
    fi
    now_s="$(date +%s)"
    delta=$(( now_s - created_s ))
    if   (( delta < 60 ));    then rel="${delta}s ago"
    elif (( delta < 3600 ));  then rel="$(( delta / 60 ))m ago"
    elif (( delta < 86400 )); then rel="$(( delta / 3600 ))h ago"
    else                           rel="$(( delta / 86400 ))d ago"
    fi

    # Status icon
    case "$status" in
      completed)
        case "$conclusion" in
          success)   icon="" ;;
          failure)   icon="" ;;
          cancelled) icon="" ;;
          skipped)   icon="⏭" ;;
          *)         icon="?" ;;
        esac
        ;;
      in_progress) icon="" ;;
      queued|waiting) icon="…" ;;
      *) icon="?" ;;
    esac

    printf '  %s  %-12s  %-30s  %s  %s\n' \
      "$icon" "$conclusion" "$name" "$sha" "$rel"
  done

# ── §2 summary counts ────────────────────────────────────────────────────────

section "Summary"

printf '%s' "$RUNS_JSON" | jq -r '
  (map(select(.status == "completed" and .conclusion == "success")) | length) as $success |
  (map(select(.status == "completed" and .conclusion == "failure")) | length) as $failure |
  (map(select(.status == "in_progress"))                           | length) as $in_prog |
  (length - $success - $failure - $in_prog)                                  as $other  |
  "  SUCCESS: \($success)   FAILURE: \($failure)   IN_PROGRESS: \($in_prog)   OTHER: \($other)"
'

echo ""
