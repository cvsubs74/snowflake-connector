#!/usr/bin/env bash
# tests/test_consistency.sh — cross-document consistency checks.
#
# These tests catch silent drift between documentation and the code that
# enforces it. Three checks, each ~one assertion:
#
# 1. Label set parity: SDLC.md ↔ label-discipline/SKILL.md
# 2. Hook inventory: filesystem ↔ README inventory ↔ settings.json
# 3. Agent topology: system-role-boundaries ↔ .claude/agents/*.md

# shellcheck source=./lib.sh
source "$(dirname "$0")/lib.sh"

echo "--- Consistency checks ---"

# ===========================================================================
# Helper: extract backtick-quoted labels from the first markdown-table column
# in <file>, scoped to lines between <start_pattern> and <end_pattern>.
# ---------------------------------------------------------------------------
extract_labels_in_section() {
  local file="$1"
  local start_re="$2"
  local end_re="$3"
  awk -v start="$start_re" -v end="$end_re" '
    $0 ~ start { in_section=1; next }
    in_section && $0 ~ end { in_section=0 }
    in_section && /^\| `[a-z]/ {
      # Extract content between first pair of backticks in column 2
      match($0, /`[^`]+`/)
      if (RSTART) {
        label = substr($0, RSTART+1, RLENGTH-2)
        print label
      }
    }
  ' "$file"
}

# ===========================================================================
# Check 1 — Label set parity: SDLC.md ↔ label-discipline/SKILL.md
# ===========================================================================
SDLC_LABELS="$(extract_labels_in_section "$REPO_ROOT/SDLC.md" '^## GitHub Label Scheme' '^## ')"
LABEL_DISCIPLINE_LABELS="$(extract_labels_in_section "$REPO_ROOT/.claude/skills/label-discipline/SKILL.md" '^## Canonical Label Table' '^## ')"

assert_set_eq "label set: SDLC.md == label-discipline/SKILL.md" \
  "$SDLC_LABELS" "$LABEL_DISCIPLINE_LABELS"

# Sanity: both label tables must have at least 10 rows. Guards against a
# regex bug returning an empty set (which would pass assert_set_eq trivially).
SDLC_COUNT="$(printf '%s\n' "$SDLC_LABELS" | sed '/^$/d' | wc -l | tr -d ' ')"
LD_COUNT="$(printf '%s\n' "$LABEL_DISCIPLINE_LABELS" | sed '/^$/d' | wc -l | tr -d ' ')"
if [[ "$SDLC_COUNT" -lt 10 || "$LD_COUNT" -lt 10 ]]; then
  printf '  FAIL  label extraction sanity (SDLC=%d, label-discipline=%d; expected >=10)\n' \
    "$SDLC_COUNT" "$LD_COUNT"
  FAIL=$(( FAIL + 1 ))
else
  printf '  PASS  label extraction sanity (>=10 rows each)\n'
  PASS=$(( PASS + 1 ))
fi

# ===========================================================================
# Check 2 — Hook inventory: filesystem ↔ README ↔ settings.json
# ===========================================================================
HOOKS_FS="$(cd "$HOOKS_DIR" && ls -1 *.sh | sort -u)"

# Extract registered hook script names (basename) from settings.json
HOOKS_SETTINGS="$(jq -r '[.hooks[][].hooks[].command] | .[]' "$REPO_ROOT/.claude/settings.json" \
  | sed 's|.*/||' | sort -u)"

# Extract from README inventory table: rows like "| 1 | `name.sh` | ..."
HOOKS_README="$(awk '
  /^## Hook inventory/ { in_section=1; next }
  in_section && /^## / { in_section=0 }
  in_section && /^\| *[0-9]+ *\| / {
    # Column 3 (1-indexed) is "| N | `file.sh` | ..." after first |
    # Easier: pull backtick-quoted .sh filename
    if (match($0, /`[a-z0-9_-]+\.sh`/)) {
      f = substr($0, RSTART+1, RLENGTH-2)
      print f
    }
  }
' "$REPO_ROOT/.claude/hooks/README.md" | sort -u)"

assert_set_eq "hook inventory: filesystem == settings.json registration" \
  "$HOOKS_FS" "$HOOKS_SETTINGS"
assert_set_eq "hook inventory: filesystem == README inventory" \
  "$HOOKS_FS" "$HOOKS_README"

# Check 2b — Hook header "Hook X of N" count matches filesystem count.
# Catches the class of drift fixed in issue #35 (headers not updated when a
# hook is added).
HOOKS_FS_COUNT="$(cd "$HOOKS_DIR" && ls -1 *.sh | wc -l | tr -d ' ')"
HOOKS_HEADER_N="$(grep -h "Hook [0-9]* of [0-9]*" "$HOOKS_DIR"/*.sh \
  | grep -o "of [0-9]*" | awk '{print $2}' | sort -u)"
if [[ "$(printf '%s\n' "$HOOKS_HEADER_N" | wc -l | tr -d ' ')" -ne 1 ]]; then
  printf '  FAIL  hook header count: headers disagree on total (values: %s)\n' "$HOOKS_HEADER_N"
  FAIL=$(( FAIL + 1 ))
elif [[ "$HOOKS_HEADER_N" -ne "$HOOKS_FS_COUNT" ]]; then
  printf '  FAIL  hook header count: headers say %s of %s but filesystem has %s hooks\n' \
    "X" "$HOOKS_HEADER_N" "$HOOKS_FS_COUNT"
  FAIL=$(( FAIL + 1 ))
else
  printf '  PASS  hook header count: all headers say "of %s" and %s .sh files exist\n' \
    "$HOOKS_HEADER_N" "$HOOKS_FS_COUNT"
  PASS=$(( PASS + 1 ))
fi

# ===========================================================================
# Check 3 — Agent topology: system-role-boundaries ↔ .claude/agents/*.md
# ---------------------------------------------------------------------------
# Filesystem: 10 agent .md files (excluding README.md).
# 8 always-on (the original SDLC team + Team Lead) + 2 on-demand specialists
# spawned via /research (research-agent, citation-agent — added in the
# Anthropic-engineering-derived expansion).
AGENTS_FS="$(cd "$REPO_ROOT/.claude/agents" && ls -1 *-agent.md 2>/dev/null | sed 's/\.md$//' | sort -u)"

EXPECTED_AGENTS="$(printf '%s\n' \
  code-reviewer-agent \
  designer-agent \
  devops-agent \
  dev-agent \
  pm-agent \
  qa-agent \
  team-lead-agent \
  triage-agent \
  research-agent \
  citation-agent | sort -u)"

assert_set_eq "agent topology: filesystem == expected 10 agents" \
  "$AGENTS_FS" "$EXPECTED_AGENTS"

# Verify each expected agent is referenced in system-role-boundaries.
# Accept any of: "agent name" (with space), "agent-name" (hyphenated), or
# the agent's short label as used in the ASCII topology (CR for Code Reviewer).
SRB="$REPO_ROOT/.claude/skills/system-role-boundaries/SKILL.md"
MISSING=""
check_ref() {
  local label="$1"; shift
  for pat in "$@"; do
    if grep -qi "$pat" "$SRB"; then return 0; fi
  done
  MISSING="$MISSING $label"
}
check_ref "pm"            "pm agent"  "pm-agent"  '| PM '
check_ref "triage"        "triage"
check_ref "dev"           "dev agent" "dev-agent" '| Dev '
check_ref "qa"            "qa agent"  "qa-agent"  '| QA '
check_ref "code-reviewer" "code reviewer"         '| CR '
check_ref "devops"        "devops"
check_ref "designer"      "designer"
check_ref "team-lead"     "team lead"             "team-lead"

if [[ -z "$MISSING" ]]; then
  printf '  PASS  every expected agent referenced in system-role-boundaries/SKILL.md\n'
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  system-role-boundaries missing references for:%s\n' "$MISSING"
  FAIL=$(( FAIL + 1 ))
fi

# ===========================================================================
print_summary
