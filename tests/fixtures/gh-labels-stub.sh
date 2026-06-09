#!/usr/bin/env bash
# tests/fixtures/gh-labels-stub.sh — script-file stub for Hook 3's
# CLAUDE_HOOK_GH_LABELS_CMD env var.
#
# Hook 3 (pr-merge-requires-in-review.sh) invokes the stub via:
#   bash -c "${CLAUDE_HOOK_GH_LABELS_CMD} ${pr_num}"
#
# We're called with $1 = PR number, must print a JSON array of label names.
# Mirrors the mock_label_cmd from the original --self-test:
#   PR 42 → ["in-review","enhancement"]
#   PR 7  → ["enhancement","in-review","priority:high"]
#   else  → ["enhancement","backlog"]
#
# A script-file stub (rather than an exported bash function) is used because
# function exports don't propagate reliably through the hook's `bash -c`
# invocation — confirmed during initial e2e verification.

case "$1" in
  42) printf '["in-review","enhancement"]' ;;
  7)  printf '["enhancement","in-review","priority:high"]' ;;
  *)  printf '["enhancement","backlog"]' ;;
esac
