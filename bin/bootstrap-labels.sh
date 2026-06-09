#!/usr/bin/env bash
# bootstrap-labels.sh — create (or update) the canonical claude-workflow label
# set on a GitHub repo. Idempotent: safe to re-run any time.
#
# Usage:
#   bin/bootstrap-labels.sh                      # uses origin remote
#   bin/bootstrap-labels.sh OWNER/REPO           # explicit target
#
# Recovery path: if an agent reports a missing label (e.g. "label 'prioritized'
# not found"), re-run this script against the repo.

set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh CLI not found. Install from https://cli.github.com/" >&2
  exit 1
fi

GITHUB_REPO="${1:-}"
if [[ "$GITHUB_REPO" == "-h" || "$GITHUB_REPO" == "--help" ]]; then
  sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi
if [[ -z "$GITHUB_REPO" ]]; then
  if git remote get-url origin >/dev/null 2>&1; then
    REMOTE_URL="$(git remote get-url origin)"
    GITHUB_REPO="$(echo "$REMOTE_URL" \
      | sed -E 's|^git@github.com:||; s|^https?://github.com/||; s|\.git$||')"
  fi
fi

if [[ -z "$GITHUB_REPO" ]]; then
  echo "Error: no repo specified and no origin remote detected." >&2
  echo "Usage: $0 OWNER/REPO" >&2
  exit 1
fi

echo "==> Bootstrapping labels on $GITHUB_REPO"

bootstrap_label() {
  local name="$1" color="$2" desc="$3"
  gh label create "$name" --color "$color" --description "$desc" --repo "$GITHUB_REPO" 2>/dev/null \
    || gh label edit "$name" --color "$color" --description "$desc" --repo "$GITHUB_REPO" 2>/dev/null \
    || { echo "  ! failed to create/edit label: $name" >&2; return 1; }
  echo "    ok  $name"
}

bootstrap_label bug               d73a4a "Regression or breakage — fast-path, skips backlog"
bootstrap_label enhancement       a2eeef "New feature, refactor, cleanup, tooling"
bootstrap_label backlog           cccccc "Awaiting PM triage"
bootstrap_label prioritized       0e8a16 "PM has triaged and approved for Dev pickup"
bootstrap_label "priority:high"   b60205 "Blocks workflow or required precondition"
bootstrap_label "priority:medium" fbca04 "Clear value, no active blocker (safe default)"
bootstrap_label "priority:low"    c2e0c6 "Cleanup, polish, nice-to-have"
bootstrap_label "in-progress"     1d76db "Dev has started"
bootstrap_label "in-review"       5319e7 "PR open, awaiting Code Reviewer"
bootstrap_label resolved          0e8a16 "QA verified post-merge (two-pass)"
bootstrap_label pm                6f42c1 "PM Agent owns / filed"
bootstrap_label qa                e99695 "QA Agent owns / filed"

echo "==> Done."
