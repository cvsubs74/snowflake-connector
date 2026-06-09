#!/usr/bin/env bash
# tests/test_hooks.sh — all hook scenario tests.
#
# Migrated from the per-hook --self-test blocks. One section per hook.
# Run via tests/run.sh, not directly (lib.sh is in the same dir).
#
# Hook 4 (session-start-doc-check) doesn't use the run_case payload pattern
# because it's a SessionStart hook driven by filesystem state — that section
# embeds its own small harness.

# shellcheck source=./lib.sh
source "$(dirname "$0")/lib.sh"

# ===========================================================================
# Hook 1 — no-direct-push-main.sh (25 cases)
# ===========================================================================
echo "--- HOOK 1: no-direct-push-main.sh ---"
HOOK="$HOOKS_DIR/no-direct-push-main.sh"

# Basic forms
run_case "$HOOK" "git push origin main"                  "git push origin main"                   "block"
run_case "$HOOK" "git push origin master"                "git push origin master"                 "block"
run_case "$HOOK" "git push --force origin main"          "git push --force origin main"           "block"
run_case "$HOOK" "git push -f origin main"               "git push -f origin main"                "block"
run_case "$HOOK" "git push -u origin main"               "git push -u origin main"                "block"

# Refspec bypass forms
run_case "$HOOK" "git push origin HEAD:main"             "git push origin HEAD:main"              "block"
run_case "$HOOK" "git push origin refs/heads/main"       "git push origin refs/heads/main"        "block"
run_case "$HOOK" "git push origin main:main"             "git push origin main:main"              "block"
run_case "$HOOK" "git push origin +main"                 "git push origin +main"                  "block"
run_case "$HOOK" "git push origin :main (delete remote)" "git push origin :main"                  "block"
run_case "$HOOK" "git push origin +main:main"            "git push origin +main:main"             "block"
run_case "$HOOK" "git push origin +refs/heads/main"      "git push origin +refs/heads/main"       "block"
run_case "$HOOK" "git push origin HEAD:refs/heads/main"  "git push origin HEAD:refs/heads/main"   "block"

# Quoted-arg bypass forms
run_case "$HOOK" "git push 'origin' 'main' (single-quoted)"        "git push 'origin' 'main'"                  "block"
run_case "$HOOK" 'git push "origin" "main" (double-quoted)'        'git push "origin" "main"'                  "block"
run_case "$HOOK" "git push 'origin' 'HEAD:main' (quoted+refspec)"  "git push 'origin' 'HEAD:main'"             "block"
run_case "$HOOK" 'git push "origin" "HEAD:refs/heads/main"'        'git push "origin" "HEAD:refs/heads/main"'  "block"

# Allow paths
run_case "$HOOK" "git push origin feat/9-branch"           "git push origin feat/9-branch"     "allow"
run_case "$HOOK" "git push origin mainline (no fp)"        "git push origin mainline"          "allow"
run_case "$HOOK" "git push origin feat/main-fix"           "git push origin feat/main-fix"     "allow"
run_case "$HOOK" "git push upstream main (different remote)" "git push upstream main"          "allow"
run_case "$HOOK" "git push 'origin' 'feat/x' (quoted, allowed)" "git push 'origin' 'feat/x'"   "allow"
CLAUDE_HOOK_TEST_BRANCH=feat/test run_case "$HOOK" "git commit -m fix (on feature branch)"   "git commit -m fix"   "allow"
CLAUDE_HOOK_TEST_BRANCH=main     run_case "$HOOK" "git commit -m fix (on main, block)"        "git commit -m fix"   "block"
run_case "$HOOK" "ls -la (non-git command)"                "ls -la"                            "allow"
CLAUDE_HOOK_BYPASS=1 run_case "$HOOK" "bypass via CLAUDE_HOOK_BYPASS=1" "git push origin main" "allow"

# ===========================================================================
# Hook 2 — restricted-label-ownership.sh (30 cases)
# ===========================================================================
echo ""
echo "--- HOOK 2: restricted-label-ownership.sh ---"
HOOK="$HOOKS_DIR/restricted-label-ownership.sh"

# PM-only labels — non-PM agents blocked
run_case "$HOOK" "dev adds priority:high"           "gh issue edit 5 --add-label priority:high"     "block" "dev-agent"
run_case "$HOOK" "dev adds prioritized"             "gh issue edit 5 --add-label prioritized"       "block" "dev-agent"
run_case "$HOOK" "qa adds priority:medium"          "gh issue edit 5 --add-label priority:medium"   "block" "qa-agent"
run_case "$HOOK" "triage adds priority:low"         "gh issue edit 5 --add-label priority:low"      "block" "triage-agent"
run_case "$HOOK" "dev adds pm label"                "gh issue edit 5 --add-label pm"                "block" "dev-agent"
run_case "$HOOK" "dev removes prioritized"          "gh issue edit 5 --remove-label prioritized"    "block" "dev-agent"

# QA-only labels — non-QA agents blocked
run_case "$HOOK" "dev adds resolved"                "gh issue edit 5 --add-label resolved"          "block" "dev-agent"
run_case "$HOOK" "pm adds resolved"                 "gh issue edit 5 --add-label resolved"          "block" "pm-agent"
run_case "$HOOK" "dev adds qa label"                "gh issue edit 5 --add-label qa"                "block" "dev-agent"
run_case "$HOOK" "pm adds qa label"                 "gh pr edit 5 --add-label qa"                   "block" "pm-agent"

# in-review — dev-only (even CR is blocked)
run_case "$HOOK" "pm adds in-review"                "gh issue edit 5 --add-label in-review"         "block" "pm-agent"
run_case "$HOOK" "qa adds in-review"                "gh pr edit 5 --add-label in-review"            "block" "qa-agent"
run_case "$HOOK" "triage removes in-review"         "gh pr edit 5 --remove-label in-review"         "block" "triage-agent"
run_case "$HOOK" "code-reviewer adds in-review"     "gh pr edit 5 --add-label in-review"            "block" "code-reviewer-agent"
run_case "$HOOK" "code-reviewer removes in-review"  "gh pr edit 5 --remove-label in-review"         "block" "code-reviewer-agent"

# PM adding its own labels
run_case "$HOOK" "pm adds priority:high (owner)"    "gh issue edit 5 --add-label priority:high"     "allow" "pm-agent"
run_case "$HOOK" "pm adds prioritized (owner)"      "gh issue edit 5 --add-label prioritized"       "allow" "pm-agent"
run_case "$HOOK" "pm adds priority:medium (owner)"  "gh issue edit 5 --add-label priority:medium"   "allow" "pm-agent"
run_case "$HOOK" "pm adds priority:low (owner)"     "gh issue edit 5 --add-label priority:low"      "allow" "pm-agent"
run_case "$HOOK" "pm adds pm label (owner)"         "gh issue edit 5 --add-label pm"                "allow" "pm-agent"

# QA adding its own labels
run_case "$HOOK" "qa adds resolved (owner)"         "gh issue edit 5 --add-label resolved"          "allow" "qa-agent"
run_case "$HOOK" "qa adds qa label (owner)"         "gh issue edit 5 --add-label qa"                "allow" "qa-agent"

# Dev adding in-review (owner)
run_case "$HOOK" "dev adds in-review (owner)"       "gh pr edit 5 --add-label in-review"            "allow" "dev-agent"

# Unrestricted labels — anyone may apply
run_case "$HOOK" "dev adds enhancement"             "gh issue edit 5 --add-label enhancement"       "allow" "dev-agent"
run_case "$HOOK" "dev adds bug"                     "gh issue edit 5 --add-label bug"               "allow" "dev-agent"
run_case "$HOOK" "qa adds backlog"                  "gh issue edit 5 --add-label backlog"           "allow" "qa-agent"

# No agent context — fail open
run_case "$HOOK" "no agent context (fail-open)"     "gh issue edit 5 --add-label prioritized"       "allow"

# Bypass + non-gh
CLAUDE_HOOK_BYPASS=1 run_case "$HOOK" "bypass via CLAUDE_HOOK_BYPASS=1" "gh issue edit 5 --add-label prioritized" "allow" "dev-agent"
run_case "$HOOK" "git push (non-gh)"                "git push origin feat/10"                       "allow" "dev-agent"
run_case "$HOOK" "ls -la (non-gh)"                  "ls -la"                                        "allow" "dev-agent"

# ===========================================================================
# Hook 3 — pr-merge-requires-in-review.sh (18 cases)
# ===========================================================================
echo ""
echo "--- HOOK 3: pr-merge-requires-in-review.sh ---"
HOOK="$HOOKS_DIR/pr-merge-requires-in-review.sh"

# Stub the gh pr view call via the script-file stub fixture
export CLAUDE_HOOK_GH_LABELS_CMD="$REPO_ROOT/tests/fixtures/gh-labels-stub.sh"

# PR without in-review — various command forms
run_case "$HOOK" "gh pr merge 5 (no in-review)"            "gh pr merge 5"                                            "block"
run_case "$HOOK" "gh pr merge --squash 5 (flag before)"    "gh pr merge --squash 5"                                   "block"
run_case "$HOOK" "gh pr merge 5 --squash (flag after)"     "gh pr merge 5 --squash"                                   "block"
run_case "$HOOK" "gh pr merge 5 --squash --delete-branch"  "gh pr merge 5 --squash --delete-branch"                   "block"
run_case "$HOOK" "gh pr merge '5' (single-quoted num)"     "gh pr merge '5'"                                          "block"
run_case "$HOOK" 'gh pr merge "5" (double-quoted num)'     'gh pr merge "5"'                                          "block"
run_case "$HOOK" "compound: cd /tmp && gh pr merge 5"      "cd /tmp && gh pr merge 5"                                 "block"
run_case "$HOOK" "URL form: gh pr merge .../pull/5"        "gh pr merge https://github.com/owner/repo/pull/5"         "block"

# PR with in-review (mock PR #42, #7)
run_case "$HOOK" "gh pr merge 42 (has in-review)"          "gh pr merge 42"                                           "allow"
run_case "$HOOK" "gh pr merge --squash 42"                 "gh pr merge --squash 42"                                  "allow"
run_case "$HOOK" "gh pr merge 7 --squash"                  "gh pr merge 7 --squash"                                   "allow"

# Non-merge gh subcommands
run_case "$HOOK" "gh pr view 5 (not merge)"                "gh pr view 5"                                             "allow"
run_case "$HOOK" "gh pr create (not merge)"                "gh pr create --title x --body y"                          "allow"
run_case "$HOOK" "gh issue close 5"                        "gh issue close 5"                                         "allow"
run_case "$HOOK" "gh issue edit 5 --add-label in-review"   "gh issue edit 5 --add-label in-review"                    "allow"
run_case "$HOOK" "ls -la (non-gh)"                         "ls -la"                                                   "allow"
run_case "$HOOK" "git push origin feat/11-branch"          "git push origin feat/11-branch"                           "allow"

# Quoted-arg false-positive regression (issues #27/#28): 'merge' inside a
# quoted argument of a non-merge gh command must not trigger the hook —
# not even as a spurious warning.
# run_case only checks exit code; these also check for silent stderr.
run_case "$HOOK" "gh pr create with 'merge' in title (no block)" \
  'gh pr create --title "merge xyz"' "allow"
# Inline stderr check — run_case only validates exit 0; we need no-noise too.
_check_no_noise() {
  local label="$1" cmd="$2"
  local payload stderr_out
  payload="$(emit_payload "$cmd")"
  stderr_out="$(printf '%s' "$payload" | CLAUDE_HOOK_GH_LABELS_CMD="$CLAUDE_HOOK_GH_LABELS_CMD" bash "$HOOK" 2>&1 >/dev/null || true)"
  if [[ -z "$stderr_out" ]]; then
    printf '  PASS  %-62s  (allow+silent)\n' "$label"
    PASS=$(( PASS + 1 ))
  else
    printf '  FAIL  %-62s  spurious stderr: %s\n' "$label" "$stderr_out"
    FAIL=$(( FAIL + 1 ))
  fi
}
_check_no_noise "gh pr create --title 'merge xyz' silent (no spurious warning)"  'gh pr create --title "merge xyz"'
_check_no_noise "grep 'gh pr merge' (non-gh, silent)"                            'grep "gh pr merge" SDLC.md'
unset -f _check_no_noise

# Bare merge at end-of-string (no trailing space or args) — detection regex
# must trigger ($ anchor in ([[:space:]]|$) matches end-of-line); the hook
# then fails open because no PR number can be extracted.
run_case "$HOOK" "bare merge at end-of-string (fail-open, allow)"  "gh pr merge"                                      "allow"

CLAUDE_HOOK_BYPASS=1 run_case "$HOOK" "bypass with blocked PR"  "gh pr merge 5"                                       "allow"

unset CLAUDE_HOOK_GH_LABELS_CMD

# ===========================================================================
# Hook 4 — session-start-doc-check.sh (7 cases)
# This hook uses --test-root + filesystem-driven assertions (not payload-
# based exit codes), so it embeds its own small harness.
# ===========================================================================
echo ""
echo "--- HOOK 4: session-start-doc-check.sh ---"
HOOK="$HOOKS_DIR/session-start-doc-check.sh"

TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

make_root() {
  local name="$1"; shift
  local dir="$TMPDIR_BASE/$name"
  mkdir -p "$dir/docs"
  for f in "$@"; do touch "$dir/$f"; done
  echo "$dir"
}

# run_case_session <label> <test_root> <expected_patterns_or_BYPASS> [env...]
# Empty string for expected_patterns = expect no stderr output at all.
run_case_session() {
  local label="$1"
  local test_root="$2"
  local expected="$3"
  shift 3
  local extra_env=("$@")

  local payload
  payload="$(jq -cn '{"session_id":"test","transcript_path":"/tmp/t"}')"

  local stderr_out exit_code=0
  stderr_out="$(
    (
      for kv in "${extra_env[@]+"${extra_env[@]}"}"; do export "$kv"; done
      printf '%s' "$payload" | bash "$HOOK" --test-root "$test_root" 2>&1 >/dev/null
    )
  )" || exit_code=$?

  if [[ "$exit_code" -ne 0 ]]; then
    printf '  FAIL  %-60s  (must exit 0; got %d)\n' "$label" "$exit_code"
    FAIL=$(( FAIL + 1 )); return
  fi

  local ok=1
  if [[ "$expected" == "BYPASS" ]]; then
    [[ -n "$stderr_out" ]] && { printf '  FAIL  %-60s  (expected silent, got: %s)\n' "$label" "$stderr_out"; ok=0; }
  elif [[ -z "$expected" ]]; then
    [[ -n "$stderr_out" ]] && { printf '  FAIL  %-60s  (unexpected output: %s)\n' "$label" "$stderr_out"; ok=0; }
  else
    for p in $expected; do
      printf '%s' "$stderr_out" | grep -q "$p" || { printf '  FAIL  %-60s  (missing "%s")\n' "$label" "$p"; ok=0; }
    done
  fi

  if [[ "$ok" -eq 1 ]]; then
    printf '  PASS  %s\n' "$label"
    PASS=$(( PASS + 1 ))
  else
    FAIL=$(( FAIL + 1 ))
  fi
}

ROOT_ALL="$(make_root all CLAUDE.md ETHOS.md SDLC.md docs/ARCHITECTURE.md)"
ROOT_NO_ETHOS="$(make_root no_ethos CLAUDE.md SDLC.md docs/ARCHITECTURE.md)"
ROOT_NO_SDLC="$(make_root no_sdlc CLAUDE.md ETHOS.md docs/ARCHITECTURE.md)"
ROOT_NO_CLAUDE="$(make_root no_claude ETHOS.md SDLC.md docs/ARCHITECTURE.md)"
ROOT_NONE="$(make_root none docs/ARCHITECTURE.md)"
ROOT_NO_ARCH="$(make_root no_arch CLAUDE.md ETHOS.md SDLC.md)"
ROOT_EMPTY="$(make_root empty)"

run_case_session "all required present (no warnings)"        "$ROOT_ALL"        ""
run_case_session "ETHOS.md missing (warning)"                "$ROOT_NO_ETHOS"   "ETHOS.md"
run_case_session "SDLC.md missing (warning)"                 "$ROOT_NO_SDLC"    "SDLC.md"
run_case_session "CLAUDE.md missing (warning)"               "$ROOT_NO_CLAUDE"  "CLAUDE.md"
run_case_session "all three required missing (warnings)"     "$ROOT_NONE"       "CLAUDE.md ETHOS.md SDLC.md"
run_case_session "docs/ARCHITECTURE.md missing (info only)"  "$ROOT_NO_ARCH"    "ARCHITECTURE.md"
run_case_session "CLAUDE_HOOK_BYPASS=1 (silent)"             "$ROOT_EMPTY"      "BYPASS" "CLAUDE_HOOK_BYPASS=1"

# Sync-check cases (use CLAUDE_HOOK_TEST_SYNC to avoid real git remote calls)
run_case_session "sync: behind by 5 — emits stale INFO"      "$ROOT_ALL"        "behind" "CLAUDE_HOOK_TEST_SYNC=behind:5"
run_case_session "sync: up to date — no INFO emitted"        "$ROOT_ALL"        ""       "CLAUDE_HOOK_TEST_SYNC=ok"
run_case_session "sync: fetch failure — emits offline INFO"  "$ROOT_ALL"        "offline" "CLAUDE_HOOK_TEST_SYNC=fetch-failed"

# ===========================================================================
# Hook 5 — pr-body-closes-check.sh (19 cases)
# Uses run_case_warn because Hook 5 always exits 0 — assertion is whether
# [HOOK WARNING] appears in stderr.
# ===========================================================================
echo ""
echo "--- HOOK 5: pr-body-closes-check.sh ---"
HOOK="$HOOKS_DIR/pr-body-closes-check.sh"

# Temp files for --body-file cases
TMP_WITH_CLOSES="$(mktemp)"
TMP_WITHOUT_CLOSES="$(mktemp)"
TMP_NONEXISTENT="/tmp/pr-body-closes-check-nonexistent-$$"
printf 'Closes #42\nSome body text\n' > "$TMP_WITH_CLOSES"
printf 'This is a PR without a closes reference\n' > "$TMP_WITHOUT_CLOSES"
rm -f "$TMP_NONEXISTENT"
# Add to the EXIT trap chain
trap 'rm -rf "$TMPDIR_BASE"; rm -f "$TMP_WITH_CLOSES" "$TMP_WITHOUT_CLOSES"' EXIT

# Allow paths (auto-close keyword present, or no body, or bypass)
run_case_warn "$HOOK" 'gh pr create --body "Closes #5"'              'gh pr create --body "Closes #5"'                  "allow"
run_case_warn "$HOOK" 'gh pr create --body "Fixes #5"'               'gh pr create --body "Fixes #5"'                   "allow"
run_case_warn "$HOOK" 'gh pr create --body "Resolves #5"'            'gh pr create --body "Resolves #5"'                "allow"
run_case_warn "$HOOK" 'gh pr create --body "Close #5"'               'gh pr create --body "Close #5"'                   "allow"
run_case_warn "$HOOK" 'gh pr create --body "Fix #5"'                 'gh pr create --body "Fix #5"'                     "allow"
run_case_warn "$HOOK" 'gh pr create --body "Resolve #5"'             'gh pr create --body "Resolve #5"'                 "allow"
run_case_warn "$HOOK" 'gh pr create --body "closes #5" (lowercase)'  'gh pr create --body "closes #5"'                  "allow"
run_case_warn "$HOOK" 'gh pr create --body "CLOSES #5" (uppercase)'  'gh pr create --body "CLOSES #5"'                  "allow"
run_case_warn "$HOOK" 'gh pr create --body multiline with Closes #5' 'gh pr create --body "## Summary\n- thing\n\nCloses #5"'  "allow"
run_case_warn "$HOOK" 'gh pr create (interactive, no body flag)'     'gh pr create'                                     "allow"
run_case_warn "$HOOK" 'gh pr create --draft (no body flag)'          'gh pr create --draft'                             "allow"
run_case_warn "$HOOK" 'gh pr create --body-file with Closes #N'      "gh pr create --body-file $TMP_WITH_CLOSES"        "allow"
run_case_warn "$HOOK" 'gh pr create --body-file nonexistent'         "gh pr create --body-file $TMP_NONEXISTENT"        "allow"
run_case_warn "$HOOK" 'compound: cd /tmp && gh pr create --body "Closes #5"' 'cd /tmp && gh pr create --body "Closes #5"' "allow"
CLAUDE_HOOK_BYPASS=1 run_case_warn "$HOOK" 'bypass via CLAUDE_HOOK_BYPASS=1' 'gh pr create --body "lorem ipsum"' "allow"
run_case_warn "$HOOK" 'git status (non-gh)'                          'git status'                                       "allow"

# Warn paths (missing auto-close keyword)
run_case_warn "$HOOK" 'gh pr create --body "lorem ipsum"'            'gh pr create --body "lorem ipsum"'                "warn"
run_case_warn "$HOOK" 'gh pr create --body "refs #5" (refs not auto-close)' 'gh pr create --body "refs #5"'             "warn"
run_case_warn "$HOOK" 'gh pr create --body-file without Closes #N'   "gh pr create --body-file $TMP_WITHOUT_CLOSES"     "warn"

# ===========================================================================
# Hook 6 — pr-merge-requires-delete-branch.sh (~18 cases)
# Blocks `gh pr merge` when --delete-branch (or -d) is absent.
# ===========================================================================
echo ""
echo "--- HOOK 6: pr-merge-requires-delete-branch.sh ---"
HOOK="$HOOKS_DIR/pr-merge-requires-delete-branch.sh"

# Block paths — missing --delete-branch
run_case "$HOOK" "gh pr merge 5 (no flags)"                "gh pr merge 5"                                            "block"
run_case "$HOOK" "gh pr merge 5 --squash"                  "gh pr merge 5 --squash"                                   "block"
run_case "$HOOK" "gh pr merge --squash 5"                  "gh pr merge --squash 5"                                   "block"
run_case "$HOOK" "gh pr merge 5 --squash --admin"          "gh pr merge 5 --squash --admin"                           "block"
run_case "$HOOK" "gh pr merge '5' (single-quoted)"         "gh pr merge '5'"                                          "block"
run_case "$HOOK" 'gh pr merge "5" (double-quoted)'         'gh pr merge "5"'                                          "block"
run_case "$HOOK" "compound: cd /tmp && gh pr merge 5"      "cd /tmp && gh pr merge 5"                                 "block"
run_case "$HOOK" "URL form: .../pull/5"                    "gh pr merge https://github.com/owner/repo/pull/5"         "block"

# Allow paths — --delete-branch or -d present
run_case "$HOOK" "gh pr merge 5 --squash --delete-branch"   "gh pr merge 5 --squash --delete-branch"                  "allow"
run_case "$HOOK" "gh pr merge 5 --delete-branch --squash"   "gh pr merge 5 --delete-branch --squash"                  "allow"
run_case "$HOOK" "gh pr merge --delete-branch 5"            "gh pr merge --delete-branch 5"                           "allow"
run_case "$HOOK" "gh pr merge 5 -d (short form)"            "gh pr merge 5 -d"                                        "allow"
run_case "$HOOK" "gh pr merge -d 5 --squash"                "gh pr merge -d 5 --squash"                               "allow"

# Allow paths — not a merge command
run_case "$HOOK" "gh pr view 5 (not merge)"                "gh pr view 5"                                             "allow"
run_case "$HOOK" "gh pr create (not merge)"                "gh pr create --title x --body y"                          "allow"
run_case "$HOOK" "gh pr create with 'merge' in title"      'gh pr create --title "block merge without flag"'          "allow"
run_case "$HOOK" "gh issue close 5"                        "gh issue close 5"                                         "allow"
run_case "$HOOK" "git push origin feat/foo"                "git push origin feat/foo"                                 "allow"
run_case "$HOOK" "ls -la (non-gh)"                         "ls -la"                                                   "allow"

# Quoted-arg false-positive regression (issue #28): 'gh pr merge' tokens
# inside a quoted argument of another command must not trigger the block.
run_case "$HOOK" "grep 'gh pr merge' in quoted arg"        'grep "gh pr merge" SDLC.md'                               "allow"
run_case "$HOOK" "echo 'gh pr merge' in quoted arg"        'echo "use gh pr merge --delete-branch"'                   "allow"
run_case "$HOOK" "--body-file workaround with merge phrase" 'gh pr create --body-file /tmp/f.txt'                     "allow"

# Bare merge at end-of-string (no trailing space or args) — detection regex
# must still fire via the $ anchor in ([[:space:]]|$); the hook then blocks
# because --delete-branch is absent (same as any other merge without the flag).
run_case "$HOOK" "bare merge at end-of-string (no flags -> block)"  "gh pr merge"                                     "block"

CLAUDE_HOOK_BYPASS=1 run_case "$HOOK" "bypass with blocked form" "gh pr merge 5 --squash" "allow"

# ===========================================================================
# Hook 7 — auto-clean-worktree.sh
#
# PostToolUse hook — always exits 0. Tests check WHAT the hook does
# (logs cleanup vs. logs warning vs. stays silent) via stderr inspection.
#
# Harness design:
#   - CLAUDE_HOOK_TEST_GH_BRANCH_CMD points to a small inline script that
#     echos a controlled branch name so we never hit the real GitHub API.
#   - CLAUDE_HOOK_TEST_REPO_ROOT points to a temp directory containing a
#     real git repo with real worktrees so git worktree list --porcelain
#     returns real data.
#   - Tests use run_case_post (defined in lib.sh):
#       "cleanup" — stderr contains "[auto-clean-worktree] Removing"
#       "warn"    — stderr contains "[auto-clean-worktree] WARNING"
#       "silent"  — none of the above
# ===========================================================================
echo ""
echo "--- HOOK 7: auto-clean-worktree.sh ---"
HOOK="$HOOKS_DIR/auto-clean-worktree.sh"

# ---------------------------------------------------------------------------
# Set up a temp git repo with a worktree for integration-style tests
# ---------------------------------------------------------------------------
HOOK7_TMPDIR="$(mktemp -d)"
HOOK7_REPO="${HOOK7_TMPDIR}/repo"
HOOK7_WT_DIR="${HOOK7_REPO}/.worktrees"
HOOK7_BRANCH="feat/99-test-hook7"

# Build a minimal git repo with one commit and one linked worktree
git init -q "$HOOK7_REPO"
git -C "$HOOK7_REPO" config user.email "test@test.com"
git -C "$HOOK7_REPO" config user.name  "Test"
echo "init" > "${HOOK7_REPO}/file.txt"
git -C "$HOOK7_REPO" add .
git -C "$HOOK7_REPO" commit -q -m "init"
git -C "$HOOK7_REPO" branch "$HOOK7_BRANCH"
mkdir -p "$HOOK7_WT_DIR"
git -C "$HOOK7_REPO" worktree add "${HOOK7_WT_DIR}/task-99" "$HOOK7_BRANCH" -q

# Branch-lookup stub: returns HOOK7_BRANCH for any PR number
BRANCH_STUB_SCRIPT="${HOOK7_TMPDIR}/branch_stub.sh"
printf '#!/usr/bin/env bash\necho "%s"\n' "$HOOK7_BRANCH" > "$BRANCH_STUB_SCRIPT"
chmod +x "$BRANCH_STUB_SCRIPT"

# Clean up temp dir on exit (appended to existing EXIT trap from Hook 5 section)
trap 'rm -rf "$TMPDIR_BASE" "$HOOK7_TMPDIR"; rm -f "$TMP_WITH_CLOSES" "$TMP_WITHOUT_CLOSES"' EXIT

# ---------------------------------------------------------------------------
# Test 1 — Not a gh pr merge command: should be silent
# ---------------------------------------------------------------------------
run_case_post "$HOOK" "git status (non-merge command)" \
  "git status" "silent"

# ---------------------------------------------------------------------------
# Test 2 — gh pr merge with stderr merge-failure phrase + non-zero exit: skip cleanup
# (issue #81 fix: field name corrected from "error" to "stderr")
# ---------------------------------------------------------------------------
# emit_post_payload now sends exit_code=1 via 4th arg; stderr is 3rd arg
HOOK7_FAIL_PAYLOAD="$(jq -cn \
  --arg cmd "gh pr merge 99 --squash --delete-branch" \
  --arg err "GraphQL: Pull Request is not mergeable." \
  '{"tool_name":"Bash","tool_input":{"command":$cmd},"tool_response":{"stdout":"","stderr":$err,"exit_code":1}}')"
HOOK7_FAIL_STDERR="$(printf '%s' "$HOOK7_FAIL_PAYLOAD" | bash "$HOOK" 2>&1 >/dev/null || true)"
if ! printf '%s' "$HOOK7_FAIL_STDERR" | command grep -q "\[auto-clean-worktree\] Removing"; then
  printf '  PASS  %-62s  (silent)\n' "gh pr merge 99 — stderr merge-failure + exit 1 → skip"
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  %-62s  expected=silent actual=cleanup\n' "gh pr merge 99 — stderr merge-failure + exit 1 → skip"
  FAIL=$(( FAIL + 1 ))
fi

# ---------------------------------------------------------------------------
# Test 3 — gh pr merge with 'not merged' in stdout: skip cleanup
# ---------------------------------------------------------------------------
run_case_post "$HOOK" "gh pr merge 99 — stdout contains 'not merged' → skip" \
  "gh pr merge 99 --squash --delete-branch" \
  "silent" "error: not merged" ""

# ---------------------------------------------------------------------------
# Test 4 — Successful merge, matching clean worktree: cleanup fires
# ---------------------------------------------------------------------------
CLAUDE_HOOK_TEST_REPO_ROOT="$HOOK7_REPO" \
CLAUDE_HOOK_TEST_GH_BRANCH_CMD="$BRANCH_STUB_SCRIPT" \
run_case_post "$HOOK" "gh pr merge 99 — clean worktree match → cleanup" \
  "gh pr merge 99 --squash --delete-branch" \
  "cleanup"

# The worktree AND branch were removed by Test 4 — recreate both for remaining tests.
# Function to recreate the branch and worktree after a cleanup test consumes them.
hook7_reset_worktree() {
  git -C "$HOOK7_REPO" branch -D "$HOOK7_BRANCH" 2>/dev/null || true
  git -C "$HOOK7_REPO" branch "$HOOK7_BRANCH" 2>/dev/null || true
  rm -rf "${HOOK7_WT_DIR}/task-99"
  git -C "$HOOK7_REPO" worktree prune -q 2>/dev/null || true
  git -C "$HOOK7_REPO" worktree add "${HOOK7_WT_DIR}/task-99" "$HOOK7_BRANCH" -q
}

hook7_reset_worktree

# ---------------------------------------------------------------------------
# Test 5 — No matching worktree (different branch): silent
# ---------------------------------------------------------------------------
MISMATCHED_STUB="${HOOK7_TMPDIR}/mismatch_stub.sh"
printf '#!/usr/bin/env bash\necho "feat/99-other-branch"\n' > "$MISMATCHED_STUB"
chmod +x "$MISMATCHED_STUB"

CLAUDE_HOOK_TEST_REPO_ROOT="$HOOK7_REPO" \
CLAUDE_HOOK_TEST_GH_BRANCH_CMD="$MISMATCHED_STUB" \
run_case_post "$HOOK" "gh pr merge 99 — no matching worktree → silent" \
  "gh pr merge 99 --squash --delete-branch" \
  "silent"

# ---------------------------------------------------------------------------
# Test 6 — Dirty worktree (uncommitted changes): warn, skip removal
# ---------------------------------------------------------------------------
printf 'dirty content\n' > "${HOOK7_WT_DIR}/task-99/dirty.txt"

CLAUDE_HOOK_TEST_REPO_ROOT="$HOOK7_REPO" \
CLAUDE_HOOK_TEST_GH_BRANCH_CMD="$BRANCH_STUB_SCRIPT" \
run_case_post "$HOOK" "gh pr merge 99 — dirty worktree → warn, skip" \
  "gh pr merge 99 --squash --delete-branch" \
  "warn"

# Clean up dirty file and restore clean worktree for subsequent tests
rm -f "${HOOK7_WT_DIR}/task-99/dirty.txt"

# ---------------------------------------------------------------------------
# Test 7 — Bypass: CLAUDE_HOOK_BYPASS=1 → always silent
# ---------------------------------------------------------------------------
CLAUDE_HOOK_BYPASS=1 \
CLAUDE_HOOK_TEST_REPO_ROOT="$HOOK7_REPO" \
CLAUDE_HOOK_TEST_GH_BRANCH_CMD="$BRANCH_STUB_SCRIPT" \
run_case_post "$HOOK" "CLAUDE_HOOK_BYPASS=1 → silent (bypass)" \
  "gh pr merge 99 --squash --delete-branch" \
  "silent"

# ---------------------------------------------------------------------------
# Test 8 — PR number extraction: URL form
# ---------------------------------------------------------------------------
CLAUDE_HOOK_TEST_REPO_ROOT="$HOOK7_REPO" \
CLAUDE_HOOK_TEST_GH_BRANCH_CMD="$BRANCH_STUB_SCRIPT" \
run_case_post "$HOOK" "gh pr merge URL form → cleanup" \
  "gh pr merge https://github.com/owner/repo/pull/99 --squash --delete-branch" \
  "cleanup"

hook7_reset_worktree

# ---------------------------------------------------------------------------
# Test 9 — gh pr merge quoted number: '99'
# ---------------------------------------------------------------------------
CLAUDE_HOOK_TEST_REPO_ROOT="$HOOK7_REPO" \
CLAUDE_HOOK_TEST_GH_BRANCH_CMD="$BRANCH_STUB_SCRIPT" \
run_case_post "$HOOK" "gh pr merge '99' (single-quoted number) → cleanup" \
  "gh pr merge '99' --squash --delete-branch" \
  "cleanup"

hook7_reset_worktree

# ---------------------------------------------------------------------------
# Test 10 — Compound command: cd /tmp && gh pr merge 99 ...
# ---------------------------------------------------------------------------
CLAUDE_HOOK_TEST_REPO_ROOT="$HOOK7_REPO" \
CLAUDE_HOOK_TEST_GH_BRANCH_CMD="$BRANCH_STUB_SCRIPT" \
run_case_post "$HOOK" "compound: cd /tmp && gh pr merge 99 → cleanup" \
  "cd /tmp && gh pr merge 99 --squash --delete-branch" \
  "cleanup"

# Prune stale worktree metadata for test 11 (uses different repo, not needed)
git -C "$HOOK7_REPO" worktree prune -q 2>/dev/null || true

# ---------------------------------------------------------------------------
# Test 11 — No .worktrees/ directory: silent (no directory, nothing to do)
# ---------------------------------------------------------------------------
HOOK7_REPO_NODIR="${HOOK7_TMPDIR}/repo_nodir"
git init -q "$HOOK7_REPO_NODIR"
git -C "$HOOK7_REPO_NODIR" config user.email "test@test.com"
git -C "$HOOK7_REPO_NODIR" config user.name  "Test"
echo "init" > "${HOOK7_REPO_NODIR}/file.txt"
git -C "$HOOK7_REPO_NODIR" add .
git -C "$HOOK7_REPO_NODIR" commit -q -m "init"

CLAUDE_HOOK_TEST_REPO_ROOT="$HOOK7_REPO_NODIR" \
CLAUDE_HOOK_TEST_GH_BRANCH_CMD="$BRANCH_STUB_SCRIPT" \
run_case_post "$HOOK" "no .worktrees/ directory → silent" \
  "gh pr merge 99 --squash --delete-branch" \
  "silent"

# ---------------------------------------------------------------------------
# Test 12 — False-positive guard: 'gh pr merge' inside a grep argument
# ---------------------------------------------------------------------------
run_case_post "$HOOK" "grep 'gh pr merge' in quoted arg → silent" \
  'grep "gh pr merge" SDLC.md' \
  "silent"

# ---------------------------------------------------------------------------
# Tests 13-16 — Issue #81 regression tests
#
# These tests validate the two hypotheses from issue #81:
#
# Test 13: FIELD NAME FIX — real runtime sends "stdout"/"stderr"/"exit_code",
#   not "output"/"error". Hook must read the right fields.
#
# Test 14: EXIT-CODE-1 NON-SUPPRESSION — gh pr merge may return exit code 1
#   when local branch deletion fails but the GitHub merge succeeded.
#   Hook must NOT bail on exit_code=1 alone when no merge-failure phrase exists
#   in stderr. (This is Hypothesis 2 from issue #81.)
#
# Tests 15-16: merge-pr.sh wrapper — validates that bin/merge-pr.sh cleans up
#   worktrees when called with a stub merge command that succeeds/fails.
# ---------------------------------------------------------------------------
echo ""
echo "--- HOOK 7 / issue #81 regression tests ---"

# Test 13 — Real runtime field names: stdout/stderr payload triggers cleanup
hook7_reset_worktree 2>/dev/null || true
REAL_FIELDS_PAYLOAD="$(jq -cn \
  --arg cmd "gh pr merge 99 --squash --delete-branch" \
  '{"tool_name":"Bash","tool_input":{"command":$cmd},"tool_response":{"stdout":"","stderr":"","exit_code":0}}')"
REAL_FIELDS_STDERR="$(
  env CLAUDE_HOOK_TEST_REPO_ROOT="$HOOK7_REPO" \
      CLAUDE_HOOK_TEST_GH_BRANCH_CMD="$BRANCH_STUB_SCRIPT" \
  bash "$HOOK" <<< "$REAL_FIELDS_PAYLOAD" 2>&1 >/dev/null || true)"
if printf '%s' "$REAL_FIELDS_STDERR" | command grep -q "\[auto-clean-worktree\] Removing"; then
  printf '  PASS  %-62s  (cleanup)\n' "real runtime fields stdout/stderr/exit_code → cleanup fires"
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  %-62s  expected=cleanup actual=silent (stderr: %s)\n' \
    "real runtime fields stdout/stderr/exit_code → cleanup fires" "$REAL_FIELDS_STDERR"
  FAIL=$(( FAIL + 1 ))
fi

hook7_reset_worktree

# Test 14 — Exit code 1 (local branch conflict) does NOT suppress cleanup
# when no merge-failure phrase is in stderr.
# This replicates the "gh pr merge returns 1 because local branch is checked out"
# scenario from Hypothesis 2 of issue #81.
EXIT1_PAYLOAD="$(jq -cn \
  --arg cmd "gh pr merge 99 --squash --delete-branch" \
  --arg err "error: Cannot delete branch 'feat/99-test-hook7' checked out at '/tmp/foo'" \
  '{"tool_name":"Bash","tool_input":{"command":$cmd},"tool_response":{"stdout":"Merged pull request #99","stderr":$err,"exit_code":1}}')"
EXIT1_STDERR="$(
  env CLAUDE_HOOK_TEST_REPO_ROOT="$HOOK7_REPO" \
      CLAUDE_HOOK_TEST_GH_BRANCH_CMD="$BRANCH_STUB_SCRIPT" \
  bash "$HOOK" <<< "$EXIT1_PAYLOAD" 2>&1 >/dev/null || true)"
if printf '%s' "$EXIT1_STDERR" | command grep -q "\[auto-clean-worktree\] Removing"; then
  printf '  PASS  %-62s  (cleanup)\n' "exit_code=1 (local-branch conflict) does NOT suppress cleanup"
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  %-62s  expected=cleanup actual=silent (stderr: %s)\n' \
    "exit_code=1 (local-branch conflict) does NOT suppress cleanup" "$EXIT1_STDERR"
  FAIL=$(( FAIL + 1 ))
fi

hook7_reset_worktree

# Test 15 — bin/merge-pr.sh: successful merge stub triggers cleanup
MERGE_PR_SCRIPT="$REPO_ROOT/bin/merge-pr.sh"
# Build a stub merge command that prints "Merged pull request" and exits 0
MERGE_SUCCESS_STUB="${HOOK7_TMPDIR}/merge_success_stub.sh"
printf '#!/usr/bin/env bash\necho "Merged pull request #99 from feat/99-test-hook7"\nexit 0\n' \
  > "$MERGE_SUCCESS_STUB"
chmod +x "$MERGE_SUCCESS_STUB"

MERGE_PR_STDERR="$(
  env CLAUDE_HOOK_TEST_REPO_ROOT="$HOOK7_REPO" \
      CLAUDE_HOOK_TEST_GH_BRANCH_CMD="$BRANCH_STUB_SCRIPT" \
      CLAUDE_HOOK_TEST_MERGE_CMD="$MERGE_SUCCESS_STUB" \
  bash "$MERGE_PR_SCRIPT" 99 --squash 2>&1 >/dev/null || true)"

if printf '%s' "$MERGE_PR_STDERR" | command grep -q "\[merge-pr\] Removing worktree"; then
  printf '  PASS  %-62s  (cleanup)\n' "bin/merge-pr.sh: success stub → worktree cleanup fires"
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  %-62s  expected cleanup log (stderr: %s)\n' \
    "bin/merge-pr.sh: success stub → worktree cleanup fires" "$MERGE_PR_STDERR"
  FAIL=$(( FAIL + 1 ))
fi

# Test 16 — bin/merge-pr.sh: failed merge stub does NOT trigger cleanup
MERGE_FAIL_STUB="${HOOK7_TMPDIR}/merge_fail_stub.sh"
printf '#!/usr/bin/env bash\necho "GraphQL: Could not resolve to a PullRequest"\nexit 1\n' \
  > "$MERGE_FAIL_STUB"
chmod +x "$MERGE_FAIL_STUB"

MERGE_FAIL_STDERR="$(
  env CLAUDE_HOOK_TEST_REPO_ROOT="$HOOK7_REPO" \
      CLAUDE_HOOK_TEST_GH_BRANCH_CMD="$BRANCH_STUB_SCRIPT" \
      CLAUDE_HOOK_TEST_MERGE_CMD="$MERGE_FAIL_STUB" \
  bash "$MERGE_PR_SCRIPT" 99 --squash 2>&1 >/dev/null || true)"

if ! printf '%s' "$MERGE_FAIL_STDERR" | command grep -q "\[merge-pr\] Removing worktree"; then
  printf '  PASS  %-62s  (no cleanup)\n' "bin/merge-pr.sh: failed merge stub → cleanup skipped"
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  %-62s  expected no cleanup (stderr: %s)\n' \
    "bin/merge-pr.sh: failed merge stub → cleanup skipped" "$MERGE_FAIL_STDERR"
  FAIL=$(( FAIL + 1 ))
fi

# ---------------------------------------------------------------------------
# Tests 17-18: Issue #87 regression — non-TTY banner suppression + local
# branch checkout conflict (both initial checks defeated simultaneously).
#
# gh v2.89.0+ suppresses the "Merged pull request" banner when stdout is
# captured in a subshell (non-TTY). When the head branch is checked out in
# a sibling worktree, gh also exits non-zero (local branch delete fails).
# Section 3 Tier 3 must detect success by calling gh pr view --json state.
# ---------------------------------------------------------------------------

# Stub that simulates the non-TTY subshell path: no banner, exits 1
MERGE_NOTTY_STUB="${HOOK7_TMPDIR}/merge_notty_stub.sh"
printf '#!/usr/bin/env bash\necho "failed to delete local branch: Cannot delete branch checked out at worktree"\nexit 1\n' \
  > "$MERGE_NOTTY_STUB"
chmod +x "$MERGE_NOTTY_STUB"

# Test 17 — non-TTY path, state=MERGED → Tier 3 detects success, cleanup fires
hook7_reset_worktree
STATE_MERGED_STUB="${HOOK7_TMPDIR}/state_merged_stub.sh"
printf '#!/usr/bin/env bash\nprintf "MERGED\\n"\nexit 0\n' > "$STATE_MERGED_STUB"
chmod +x "$STATE_MERGED_STUB"

NOTTY_MERGED_STDERR="$(
  env CLAUDE_HOOK_TEST_REPO_ROOT="$HOOK7_REPO" \
      CLAUDE_HOOK_TEST_GH_BRANCH_CMD="$BRANCH_STUB_SCRIPT" \
      CLAUDE_HOOK_TEST_MERGE_CMD="$MERGE_NOTTY_STUB" \
      CLAUDE_HOOK_TEST_PR_STATE_CMD="$STATE_MERGED_STUB" \
  bash "$MERGE_PR_SCRIPT" 99 --squash 2>&1 >/dev/null || true)"

if printf '%s' "$NOTTY_MERGED_STDERR" | command grep -q "\[merge-pr\] Removing worktree"; then
  printf '  PASS  %-62s  (cleanup)\n' "non-TTY+exit1, state=MERGED → Tier 3 cleanup fires"
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  %-62s  expected cleanup log (stderr: %s)\n' \
    "non-TTY+exit1, state=MERGED → Tier 3 cleanup fires" "$NOTTY_MERGED_STDERR"
  FAIL=$(( FAIL + 1 ))
fi

# Test 18 — non-TTY path, state=OPEN → Tier 3 does NOT treat as success
hook7_reset_worktree
STATE_OPEN_STUB="${HOOK7_TMPDIR}/state_open_stub.sh"
printf '#!/usr/bin/env bash\nprintf "OPEN\\n"\nexit 0\n' > "$STATE_OPEN_STUB"
chmod +x "$STATE_OPEN_STUB"

NOTTY_OPEN_STDERR="$(
  env CLAUDE_HOOK_TEST_REPO_ROOT="$HOOK7_REPO" \
      CLAUDE_HOOK_TEST_GH_BRANCH_CMD="$BRANCH_STUB_SCRIPT" \
      CLAUDE_HOOK_TEST_MERGE_CMD="$MERGE_NOTTY_STUB" \
      CLAUDE_HOOK_TEST_PR_STATE_CMD="$STATE_OPEN_STUB" \
  bash "$MERGE_PR_SCRIPT" 99 --squash 2>&1 >/dev/null || true)"

if ! printf '%s' "$NOTTY_OPEN_STDERR" | command grep -q "\[merge-pr\] Removing worktree"; then
  printf '  PASS  %-62s  (no cleanup)\n' "non-TTY+exit1, state=OPEN → cleanup correctly skipped"
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  %-62s  expected no cleanup (stderr: %s)\n' \
    "non-TTY+exit1, state=OPEN → cleanup correctly skipped" "$NOTTY_OPEN_STDERR"
  FAIL=$(( FAIL + 1 ))
fi

# ===========================================================================
print_summary
