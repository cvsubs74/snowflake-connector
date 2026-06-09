#!/usr/bin/env bash
# team-status.sh — one-shot snapshot of the agent team's queue state.
# Mirrors Team Lead's cold-start anchor commands so operators can see
# what's in flight without spawning a Team Lead session.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── helpers ─────────────────────────────────────────────────────────────────

section() {
  echo ""
  echo "── $1 ──────────────────────────────────────────────────────────────"
}

# ── §1 local branch + sync status ───────────────────────────────────────────

section "Branch / Sync"
git -C "$REPO_ROOT" status -sb 2>/dev/null || echo "(git status unavailable)"

# ── github auth check ────────────────────────────────────────────────────────

GH_OK=0
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    GH_OK=1
  else
    echo "" >&2
    echo "NOTE: gh CLI not authenticated — skipping GitHub sections." >&2
    echo "      Run \`gh auth login\` to enable full output." >&2
  fi
else
  echo "" >&2
  echo "NOTE: gh CLI not found — skipping GitHub sections." >&2
fi

if [[ "$GH_OK" -eq 0 ]]; then
  section "Last 5 merges to origin/main"
  git -C "$REPO_ROOT" log origin/main --oneline -5 2>/dev/null \
    || echo "(git log unavailable)"
  echo ""
  exit 0
fi

# ── §2 open PRs ──────────────────────────────────────────────────────────────

section "Open PRs"
PR_JSON="$(gh pr list --state open --json number,title,labels 2>/dev/null || echo '[]')"
PR_COUNT="$(printf '%s' "$PR_JSON" | jq 'length')"
if [[ "$PR_COUNT" -eq 0 ]]; then
  echo "  (none)"
else
  printf '%s' "$PR_JSON" | jq -r '.[] |
    "#\(.number) \(.title) — [\(.labels | map(.name) | join(", "))]"' \
    | sed 's/^/  /'
fi

# ── §3 prioritized open issues ───────────────────────────────────────────────

section "Prioritized Issues"
PI_JSON="$(gh issue list --label prioritized --state open \
  --json number,title,labels 2>/dev/null || echo '[]')"
PI_COUNT="$(printf '%s' "$PI_JSON" | jq 'length')"
if [[ "$PI_COUNT" -eq 0 ]]; then
  echo "  (none)"
else
  printf '%s' "$PI_JSON" | jq -r '.[] |
    . as $i |
    ($i.labels | map(.name) | map(select(startswith("priority:"))) | first // "priority:?") as $pri |
    "  #\($i.number) [\($pri)] \($i.title)"'
fi

# ── §4 open bugs ─────────────────────────────────────────────────────────────

section "Open Bugs"
BUG_JSON="$(gh issue list --label bug --state open \
  --json number,title 2>/dev/null || echo '[]')"
BUG_COUNT="$(printf '%s' "$BUG_JSON" | jq 'length')"
if [[ "$BUG_COUNT" -eq 0 ]]; then
  echo "  (none)"
else
  printf '%s' "$BUG_JSON" | jq -r '.[] | "  #\(.number) \(.title)"'
fi

# ── §5 last 5 merges to origin/main ──────────────────────────────────────────

section "Last 5 merges to origin/main"
git -C "$REPO_ROOT" log origin/main --oneline -5 2>/dev/null \
  || echo "  (git log unavailable)"

echo ""
