#!/usr/bin/env bash
# tests/test_repo.sh — repo structure sanity.
#
# Cheap checks that catch broken configuration before any other test runs:
#   - settings.json parses, registered hook paths exist and are executable
#   - 8 expected agents present
#   - 5 expected skills present, each with a SKILL.md
#   - required cold-start docs present at repo root
#   - bin/*.sh pass `bash -n` syntax

# shellcheck source=./lib.sh
source "$(dirname "$0")/lib.sh"

echo "--- Repo structure ---"

# ===========================================================================
# settings.json valid + hook paths resolve
# ===========================================================================
SETTINGS="$REPO_ROOT/.claude/settings.json"
if jq -e . "$SETTINGS" >/dev/null 2>&1; then
  printf '  PASS  .claude/settings.json is valid JSON\n'
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  .claude/settings.json is NOT valid JSON\n'
  FAIL=$(( FAIL + 1 ))
fi

# Every registered hook command must resolve to an executable file under repo root
HOOK_PATHS="$(jq -r '[.hooks[][].hooks[].command] | .[]' "$SETTINGS")"
all_ok=1
while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  if [[ ! -x "$REPO_ROOT/$p" ]]; then
    printf '  FAIL  registered hook not executable: %s\n' "$p"
    all_ok=0
    FAIL=$(( FAIL + 1 ))
  fi
done <<< "$HOOK_PATHS"
if [[ "$all_ok" -eq 1 ]]; then
  printf '  PASS  all registered hook scripts are executable\n'
  PASS=$(( PASS + 1 ))
fi

# ===========================================================================
# Required cold-start docs at repo root
# ===========================================================================
for doc in CLAUDE.md ETHOS.md SDLC.md; do
  if [[ -f "$REPO_ROOT/$doc" ]]; then
    printf '  PASS  required doc present: %s\n' "$doc"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  required doc missing: %s\n' "$doc"
    FAIL=$(( FAIL + 1 ))
  fi
done

# ===========================================================================
# 8 agent files present
# ===========================================================================
for agent in pm-agent dev-agent qa-agent triage-agent code-reviewer-agent devops-agent designer-agent team-lead-agent; do
  if [[ -f "$REPO_ROOT/.claude/agents/$agent.md" ]]; then
    printf '  PASS  agent present: %s\n' "$agent"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  agent missing: %s\n' "$agent"
    FAIL=$(( FAIL + 1 ))
  fi
done

# ===========================================================================
# 5 skill directories with SKILL.md
# ===========================================================================
for skill in file-bug-issue label-discipline skill-maintenance system-role-boundaries worktree-management; do
  if [[ -f "$REPO_ROOT/.claude/skills/$skill/SKILL.md" ]]; then
    printf '  PASS  skill present: %s\n' "$skill"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  skill missing SKILL.md: %s\n' "$skill"
    FAIL=$(( FAIL + 1 ))
  fi
done

# ===========================================================================
# bin/*.sh pass syntax check
# ===========================================================================
for f in "$REPO_ROOT"/bin/*.sh; do
  [[ -f "$f" ]] || continue
  name="$(basename "$f")"
  if bash -n "$f" 2>/dev/null; then
    printf '  PASS  bash -n %s\n' "$name"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  bash -n %s (syntax error)\n' "$name"
    FAIL=$(( FAIL + 1 ))
  fi
done

# ===========================================================================
# Each hook script passes bash -n
# ===========================================================================
for f in "$REPO_ROOT"/.claude/hooks/*.sh; do
  [[ -f "$f" ]] || continue
  name="$(basename "$f")"
  if bash -n "$f" 2>/dev/null; then
    printf '  PASS  bash -n .claude/hooks/%s\n' "$name"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  bash -n .claude/hooks/%s (syntax error)\n' "$name"
    FAIL=$(( FAIL + 1 ))
  fi
done

# ===========================================================================
print_summary
