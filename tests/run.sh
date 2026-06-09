#!/usr/bin/env bash
# tests/run.sh — entry point for the test suite.
#
# Discovers every tests/test_*.sh file, runs each in its own bash process,
# aggregates pass/fail counts. Returns non-zero if any test file fails.
#
# Usage:
#   bash tests/run.sh                  # run all
#   bash tests/run.sh test_hooks.sh    # run one (positional filename)
#
# Each test file is expected to:
#   - Source ./lib.sh (relative to tests/)
#   - Run its assertions
#   - Call print_summary at the end (sets exit code)

set -uo pipefail

cd "$(dirname "$0")/.."

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required. Install with: brew install jq (macOS) or apt-get install jq (linux)" >&2
  exit 1
fi

FILES_PASS=0
FILES_FAIL=0

if [[ $# -gt 0 ]]; then
  TARGETS=("tests/$1")
else
  TARGETS=(tests/test_*.sh)
fi

for f in "${TARGETS[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: no such test file: $f" >&2
    exit 1
  fi
  echo "=== $(basename "$f") ==="
  if bash "$f"; then
    FILES_PASS=$(( FILES_PASS + 1 ))
  else
    FILES_FAIL=$(( FILES_FAIL + 1 ))
  fi
  echo ""
done

echo "=========================================="
echo "  ${FILES_PASS} files passed, ${FILES_FAIL} files failed"
echo "=========================================="
[[ "$FILES_FAIL" -eq 0 ]]
