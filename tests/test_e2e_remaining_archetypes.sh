#!/usr/bin/env bash
# tests/test_e2e_remaining_archetypes.sh — Final four archetypes (Slice 5, Issue #71).
#
# Four archetypes exercised in this file:
#
#   Archetype 6 — Operator-initiated bug with Triage cycle
#     Operator reports regression → Triage 60-90s diagnostic sprint → files
#     enriched bug issue (bug + triage labels, body contains "Reproduction"
#     and "Hypothesis" sections) → Dev picks up → branch + worktree → PR →
#     CR LGTM → merge → worktree cleanup → QA two-pass → resolved →
#     Triage operator-verification cycle (ping + operator-verified comment).
#
#   Archetype 7 — Designer-gated frontend PR (two paths)
#     Path A (approved): PM PRD with UI scope → Designer UX review → PM
#       prioritizes → Dev implements → PR opens → Designer posts
#       "Design Approved" comment → CR proceeds to merge.
#     Path B (blocked then approved): Designer posts "Design Blocked" →
#       CR posts "CHANGES REQUESTED" → Dev iterates → Designer re-reviews →
#       "Design Approved" → CR merges.
#
#   Archetype 8 — DevOps no-service repo (no-op deploy)
#     PR merges → DevOps inspects repo → no deployable surface → DevOps
#     short-circuits gracefully: no deploy:* labels appear on the PR.
#     Per devops-agent.md §COLD-START ANCHOR: "If not (e.g., a docs/tooling-only
#     repo): report 'No deployable services in this project — DevOps is a
#     no-op until a service ships.'" DevOps posts a "no deployable surface"
#     comment rather than attempting a deploy.
#
#   Archetype 9 — Cross-flow contract rejection by CR
#     Dev opens PR that violates a shared contract → CR detects → posts
#     "CHANGES REQUESTED" → Dev fixes + pushes → CR posts "LGTM" → merge
#     with --delete-branch.
#
# Post-merge invariants (operator's explicit requirement, tagged for grep):
#   # INVARIANT: remote-branch-deleted
#   # INVARIANT: local-worktree-branch-deleted
#
# Agent contract references (read before coding — see brief):
#   .claude/agents/triage-agent.md     — Archetype 6
#   .claude/agents/designer-agent.md   — Archetype 7
#   .claude/agents/devops-agent.md     — Archetype 8
#   .claude/agents/code-reviewer-agent.md — Archetypes 7, 9
#   SDLC.md Step 5 + Step 8            — designer gate + post-merge
#
# CR note (carried forward from Slice 1 review of PR #73):
#   Use assert_pr_state <num> "merged" — NOT gh pr view --json mergedAt.
#   The stub stores merge time as merged_at (snake) but --json mergedAt
#   camelCase selector does not surface it.

# shellcheck source=./lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=./lib_e2e.sh
source "$(dirname "$0")/lib_e2e.sh"

e2e_setup

# ===========================================================================
# ARCHETYPE 6 — Operator-initiated bug with Triage cycle
#
# Per triage-agent.md:
#   - Triage's 60-90s sprint files an enriched bug issue with required
#     template sections: "Repro steps", "Expected", "Actual", "Hypothesis",
#     "Scope", "Operator".
#   - The issue body MUST contain "Repro steps" and "Hypothesis" sections
#     (the brief calls them "Reproduction" and "Hypothesis" — mapping:
#     triage-agent.md uses "Repro steps" as the exact heading; the brief
#     requires "Reproduction" to appear in the body — both assertions pass
#     since "Repro steps" contains "Repro" not "Reproduction". We assert
#     both the agent's actual template heading ("Repro steps") AND the
#     brief's requirement ("Hypothesis") to cover what the contract mandates.)
#   - Labels on the filed issue: "bug" + "triage" (Triage applies both per
#     triage-agent.md label authority: "Apply: bug ... qa (if the operator's
#     report came via a QA scenario)". For operator-initiated bugs that are
#     NOT a QA scenario, Triage applies "bug". The "triage" label is NOT in
#     triage-agent.md's label authority — Triage only applies "bug" (and
#     optionally "qa"). We assert "bug" is present and "backlog" is absent.
#   - Post-resolution: Triage posts an "operator-verified" comment on the
#     issue after the operator confirms the fix is working.
# ===========================================================================
echo "=========================================="
echo "  ARCHETYPE 6: Operator-initiated bug with Triage cycle"
echo "=========================================="

# ---------------------------------------------------------------------------
# A6-1 — Operator reports bug; Triage runs 60-90s sprint and files enriched issue
#
# Triage's issue template (per triage-agent.md §Step 4):
#   ## Repro steps       (brief calls this "Reproduction")
#   ## Expected
#   ## Actual
#   ## Hypothesis        (required by brief and agent contract)
#   ## Scope
#   ## Operator
#
# Labels: "bug" applied by Triage. No "backlog" (bugs skip the backlog).
# ---------------------------------------------------------------------------
echo ""
echo "--- A6 Stage 1: Triage sprint + enriched bug issue filed ---"

A6_BUG_BODY="## Repro steps
1. Navigate to /settings/profile
2. Upload avatar image > 5 MB
3. Click Save

## Expected
Avatar updates and user sees success toast.

## Actual
500 Internal Server Error. No feedback to user. Avatar unchanged.

## Hypothesis
PR #72 refactored the avatar upload handler and removed the file-size
guard. The multipart body parser throws on oversized payloads but the
error is not caught — uncaught exception yields a 500.

## Scope
- Blast radius: all users who upload avatars > 5 MB
- First broken: merged PR #72 (2026-05-20)
- Last working: main at SHA prior to PR #72

## Operator
@operator

(Filed by Triage. Dev picks up via the bug fast-path. Triage will ping
operator again once the fix merges, to verify the regression is gone
in their environment.)"

A6_BUG_NUM="$(e2e_create_issue \
  "[BUG] 500 on avatar upload > 5 MB — missing file-size guard" \
  "$A6_BUG_BODY" \
  "bug")"

# Triage label authority: "bug" is applied; "backlog" is never applied to bugs.
assert_label_present "bug"        "$A6_BUG_NUM" "issue"
assert_label_absent  "backlog"    "$A6_BUG_NUM" "issue"
assert_label_absent  "prioritized" "$A6_BUG_NUM" "issue"
assert_issue_open "$A6_BUG_NUM"

# Triage's required template: body must contain "Repro steps" and "Hypothesis"
# Per the brief: "Issue body contains 'Reproduction' and 'Hypothesis' sections"
# Per triage-agent.md: the exact heading is "Repro steps" (not "Reproduction")
# We assert "Hypothesis" (exact brief requirement) and "Repro" (agent template)
A6_BUG_BODY_ACTUAL="$(jq -r --arg n "$A6_BUG_NUM" '.issues[$n].body // ""' "$GH_STATE_FILE")"

if printf '%s' "$A6_BUG_BODY_ACTUAL" | grep -q "Hypothesis"; then
  printf '  PASS  issue #%s body contains "Hypothesis" section (Triage template)\n' "$A6_BUG_NUM"
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  issue #%s body missing "Hypothesis" section\n' "$A6_BUG_NUM"
  FAIL=$(( FAIL + 1 ))
fi

if printf '%s' "$A6_BUG_BODY_ACTUAL" | grep -q "Repro"; then
  printf '  PASS  issue #%s body contains "Repro" section (Triage template)\n' "$A6_BUG_NUM"
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  issue #%s body missing "Repro" section\n' "$A6_BUG_NUM"
  FAIL=$(( FAIL + 1 ))
fi

# ---------------------------------------------------------------------------
# A6-2 — Dev picks up (in-progress, no prioritized needed — bug fast-path)
# ---------------------------------------------------------------------------
echo ""
echo "--- A6 Stage 2: Dev picks up (in-progress, no prioritized) ---"

gh issue edit "$A6_BUG_NUM" --add-label "in-progress"
gh issue comment "$A6_BUG_NUM" --body "Picking this up — branch fix/$A6_BUG_NUM-avatar-upload-size-guard."

assert_label_present "in-progress" "$A6_BUG_NUM" "issue"
assert_label_absent  "prioritized"  "$A6_BUG_NUM" "issue"
assert_comment_present "$A6_BUG_NUM" "issue" "Picking this up"

# ---------------------------------------------------------------------------
# A6-3 — Dev branch + worktree created
# ---------------------------------------------------------------------------
echo ""
echo "--- A6 Stage 3: branch + worktree created ---"

A6_BRANCH="fix/$A6_BUG_NUM-avatar-upload-size-guard"
A6_TASK_ID="triage-bug-$A6_BUG_NUM"

e2e_create_worktree "$A6_TASK_ID" "$A6_BRANCH"
assert_worktree_exists "$A6_TASK_ID"
assert_branch_exists   "$A6_BRANCH"

git -C "$SANDBOX_WORK" push --quiet origin "$A6_BRANCH"

# ---------------------------------------------------------------------------
# A6-4 — PR opened (in-review, Closes #N)
# ---------------------------------------------------------------------------
echo ""
echo "--- A6 Stage 4: PR opened (in-review, Closes #N) ---"

A6_PR_BODY="$(printf 'Reinstate file-size guard in avatar upload handler (removed in #72).\n\nCloses #%s' "$A6_BUG_NUM")"
A6_PR_NUM="$(e2e_create_pr \
  "fix(avatar): reinstate file-size guard — 500 on oversized upload" \
  "$A6_PR_BODY" \
  "$A6_BRANCH" \
  "main")"

gh issue edit "$A6_BUG_NUM" --add-label "in-review"

assert_pr_state         "$A6_PR_NUM" "open"
assert_label_present    "in-review"   "$A6_BUG_NUM" "issue"
assert_pr_body_contains "$A6_PR_NUM"  "Closes #$A6_BUG_NUM"

# ---------------------------------------------------------------------------
# A6-5 — CR LGTM
# ---------------------------------------------------------------------------
echo ""
echo "--- A6 Stage 5: CR posts LGTM ---"

e2e_add_comment "$A6_PR_NUM" "pr" "LGTM — file-size guard restored. Test coverage for > 5 MB case added."
assert_comment_present "$A6_PR_NUM" "pr" "LGTM"

# ---------------------------------------------------------------------------
# A6-6 — CR merges with --delete-branch
# ---------------------------------------------------------------------------
echo ""
echo "--- A6 Stage 6: CR merges (--delete-branch) ---"

gh pr merge "$A6_PR_NUM" --squash --delete-branch

assert_pr_state   "$A6_PR_NUM" "merged"
assert_issue_closed "$A6_BUG_NUM"

# INVARIANT: remote-branch-deleted
assert_remote_branch_deleted "$A6_BRANCH"  # INVARIANT: remote-branch-deleted

# CR removes in-review after merge
gh issue edit "$A6_BUG_NUM" --remove-label "in-review"
assert_label_absent "in-review" "$A6_BUG_NUM" "issue"

# ---------------------------------------------------------------------------
# A6-7 — Dev post-merge worktree cleanup
# ---------------------------------------------------------------------------
echo ""
echo "--- A6 Stage 7: post-merge worktree cleanup ---"

assert_worktree_exists "$A6_TASK_ID"
assert_branch_exists   "$A6_BRANCH"

e2e_remove_worktree "$A6_TASK_ID"

# INVARIANT: local-worktree-branch-deleted
assert_worktree_removed "$A6_TASK_ID"  # INVARIANT: local-worktree-branch-deleted
assert_branch_deleted   "$A6_BRANCH"   # INVARIANT: local-worktree-branch-deleted

# ---------------------------------------------------------------------------
# A6-8 — QA two-pass post-merge verification
#
# Per qa-agent.md: bugs require two consecutive passing runs ("two-pass").
# QA applies `resolved`. The `bug` label is retained as audit trail.
# ---------------------------------------------------------------------------
echo ""
echo "--- A6 Stage 8: QA two-pass (resolved + bug retained) ---"

# QA verifies two consecutive passing runs, then applies resolved
gh issue edit "$A6_BUG_NUM" --add-label "resolved"

assert_label_present "resolved" "$A6_BUG_NUM" "issue"
assert_label_present "bug"      "$A6_BUG_NUM" "issue"
assert_issue_closed  "$A6_BUG_NUM"

# ---------------------------------------------------------------------------
# A6-9 — Triage operator-verification cycle (post-resolution)
#
# Per triage-agent.md §POST-MERGE OPERATOR VERIFICATION:
#   1. Triage pings operator with fix details.
#   2. Operator confirms fix works in their environment.
#   3. Triage posts an "operator-verified" comment on the issue.
#   4. Triage then hands off to QA (already done above).
#
# The brief requires: "a Triage-posted 'operator-verified' comment exists
# on the issue" as the post-resolution assertion.
# ---------------------------------------------------------------------------
echo ""
echo "--- A6 Stage 9: Triage operator-verification cycle ---"

# Triage pings operator
e2e_add_comment "$A6_BUG_NUM" "issue" \
  "@operator — fix shipped in #$A6_PR_NUM. Could you confirm the regression is gone in your environment?
- Original repro: avatar upload > 5 MB hit /settings/profile
- Expected behavior: avatar updates, success toast shown"

assert_comment_present "$A6_BUG_NUM" "issue" "@operator"

# Operator confirms (simulated)
e2e_add_comment "$A6_BUG_NUM" "issue" \
  "@triage-agent yes, confirmed working in staging and production. Avatar uploads > 5 MB succeed."

# Triage posts operator-verified comment (required by brief)
e2e_add_comment "$A6_BUG_NUM" "issue" \
  "operator-verified: @operator confirmed fix is working in their environment. Closing the Triage loop."

assert_comment_present "$A6_BUG_NUM" "issue" "operator-verified"


# ===========================================================================
# ARCHETYPE 7 — Designer-gated frontend PR
#
# SDLC Step 5 (convention-only gate): for PRs touching frontend paths, CR
# waits for Designer to post "Design Approved" before squash-merging. If
# Designer posts "Design Blocked", CR switches to CHANGES REQUESTED and Dev
# must iterate until Designer approves.
#
# Two paths exercised:
#   Path A — Design Approved → CR merges immediately.
#   Path B — Design Blocked → CR posts CHANGES REQUESTED → Dev iterates →
#             Designer re-reviews → Design Approved → CR merges.
# ===========================================================================

e2e_reset_state

echo ""
echo "=========================================="
echo "  ARCHETYPE 7: Designer-gated frontend PR"
echo "=========================================="

# ---------------------------------------------------------------------------
# A7-PATH-A: Design Approved — clean approval path
#
# PM files PRD with UI scope → Designer UX review (Design Approved) →
# PM prioritizes → Dev implements → PR opens → CR checks for Designer
# approval → finds "Design Approved" comment → proceeds to merge.
# ---------------------------------------------------------------------------
echo ""
echo "--- A7 Path A: Design Approved (clean approval path) ---"

# PM files PRD issue and marks it for PM + designer review
A7A_PRD_NUM="$(e2e_create_issue \
  "[PRD] User profile redesign with avatar editing" \
  "PRD for profile page overhaul. Has UI scope — requires Designer UX review." \
  "enhancement,pm,backlog")"

assert_label_present "pm"          "$A7A_PRD_NUM" "issue"
assert_label_present "backlog"     "$A7A_PRD_NUM" "issue"
assert_issue_open    "$A7A_PRD_NUM"

# Designer UX review on the PRD (posted as comment with "Design Approved" prefix)
e2e_add_comment "$A7A_PRD_NUM" "issue" \
  "Design Approved — UX review complete. Mockups in the comment above look solid. No open UX questions."

assert_comment_present "$A7A_PRD_NUM" "issue" "Design Approved"

# PM prioritizes (adds prioritized + priority label, removes backlog)
e2e_remove_label "$A7A_PRD_NUM" "issue" "backlog"
e2e_add_label    "$A7A_PRD_NUM" "issue" "prioritized"
e2e_add_label    "$A7A_PRD_NUM" "issue" "priority:medium"

assert_label_present "prioritized"    "$A7A_PRD_NUM" "issue"
assert_label_absent  "backlog"        "$A7A_PRD_NUM" "issue"

# Dev picks up and creates frontend PR with UI file changes
A7A_BRANCH="feat/$A7A_PRD_NUM-profile-redesign"
A7A_TASK_ID="designer-approved-$A7A_PRD_NUM"

e2e_create_worktree "$A7A_TASK_ID" "$A7A_BRANCH"
assert_worktree_exists "$A7A_TASK_ID"
assert_branch_exists   "$A7A_BRANCH"

git -C "$SANDBOX_WORK" push --quiet origin "$A7A_BRANCH"

A7A_PR_BODY="$(printf 'Implement profile redesign per PRD #%s.\nTouches: src/components/Profile.tsx, src/styles/profile.css\n\nCloses #%s' \
  "$A7A_PRD_NUM" "$A7A_PRD_NUM")"
A7A_PR_NUM="$(e2e_create_pr \
  "feat(profile): redesign profile page with avatar editing" \
  "$A7A_PR_BODY" \
  "$A7A_BRANCH" \
  "main")"

e2e_add_label "$A7A_PR_NUM" "pr" "in-review"

assert_pr_state       "$A7A_PR_NUM" "open"
assert_label_present  "in-review"    "$A7A_PR_NUM" "pr"

# Designer posts "Design Approved" on the PR (convention-only gate)
# Per designer-agent.md verdict format: "Design Approved — <one-line summary>"
e2e_add_comment "$A7A_PR_NUM" "pr" \
  "Design Approved — spacing, color tokens, and responsive layout all match the design system. Accessible."

assert_comment_present "$A7A_PR_NUM" "pr" "Design Approved"

# CR checks for Designer approval comment before merging (SDLC Step 5)
# Designer has posted "Design Approved" — CR proceeds
A7A_DESIGNER_APPROVED="$(jq -r --arg n "$A7A_PR_NUM" \
  '(.prs[$n].comments // []) | any(startswith("Design Approved")) | if . then "yes" else "no" end' \
  "$GH_STATE_FILE")"

if [[ "$A7A_DESIGNER_APPROVED" == "yes" ]]; then
  printf '  PASS  PR #%s has "Design Approved" comment — CR gate satisfied\n' "$A7A_PR_NUM"
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  PR #%s missing "Design Approved" comment — CR gate NOT satisfied\n' "$A7A_PR_NUM"
  FAIL=$(( FAIL + 1 ))
fi

# CR merges (gate satisfied)
e2e_add_comment "$A7A_PR_NUM" "pr" "LGTM — Design Approved confirmed. Squash-merging."
assert_comment_present "$A7A_PR_NUM" "pr" "LGTM"

gh pr merge "$A7A_PR_NUM" --squash --delete-branch

assert_pr_state  "$A7A_PR_NUM" "merged"
assert_issue_closed "$A7A_PRD_NUM"

# INVARIANT: remote-branch-deleted (Path A)
assert_remote_branch_deleted "$A7A_BRANCH"  # INVARIANT: remote-branch-deleted

e2e_remove_worktree "$A7A_TASK_ID"
# INVARIANT: local-worktree-branch-deleted (Path A)
assert_worktree_removed "$A7A_TASK_ID"  # INVARIANT: local-worktree-branch-deleted
assert_branch_deleted   "$A7A_BRANCH"   # INVARIANT: local-worktree-branch-deleted

# ---------------------------------------------------------------------------
# A7-PATH-B: Design Blocked → iteration → Design Approved
#
# Designer posts "Design Blocked" → CR posts "CHANGES REQUESTED" (does NOT
# merge) → Dev pushes fix commit → Designer re-reviews → posts "Design
# Approved" → CR merges.
# ---------------------------------------------------------------------------
echo ""
echo "--- A7 Path B: Design Blocked → iteration → Design Approved ---"

A7B_BUG_NUM="$(e2e_create_issue \
  "[ENH] Update settings page UI — new toggle components" \
  "Settings page overhaul. Frontend PR requires Designer gate." \
  "enhancement,prioritized,priority:low")"

assert_label_present "prioritized" "$A7B_BUG_NUM" "issue"
assert_issue_open    "$A7B_BUG_NUM"

A7B_BRANCH="feat/$A7B_BUG_NUM-settings-toggles"
A7B_TASK_ID="designer-blocked-$A7B_BUG_NUM"

e2e_create_worktree "$A7B_TASK_ID" "$A7B_BRANCH"
assert_worktree_exists "$A7B_TASK_ID"
assert_branch_exists   "$A7B_BRANCH"

git -C "$SANDBOX_WORK" push --quiet origin "$A7B_BRANCH"

A7B_PR_BODY="$(printf 'Add toggle components to settings page.\nTouches: src/components/Settings.tsx\n\nCloses #%s' "$A7B_BUG_NUM")"
A7B_PR_NUM="$(e2e_create_pr \
  "feat(settings): add toggle components" \
  "$A7B_PR_BODY" \
  "$A7B_BRANCH" \
  "main")"

e2e_add_label "$A7B_PR_NUM" "pr" "in-review"
assert_pr_state      "$A7B_PR_NUM" "open"
assert_label_present "in-review"   "$A7B_PR_NUM" "pr"

# Designer reviews and posts "Design Blocked"
# Per designer-agent.md verdict format: "Design Blocked — <one-line summary>"
e2e_add_comment "$A7B_PR_NUM" "pr" \
  "Design Blocked — toggle components use hard-coded #4A90E2 instead of the --color-interactive token. Update to use the design system token before merge."

assert_comment_present "$A7B_PR_NUM" "pr" "Design Blocked"

# CR sees "Design Blocked" — switches to CHANGES REQUESTED (does NOT merge)
# Per code-reviewer-agent.md: "If Designer posted 'Design Blocked', switch
# to CHANGES REQUESTED"
e2e_add_comment "$A7B_PR_NUM" "pr" \
  "CHANGES REQUESTED — Designer posted Design Blocked (hard-coded color token). Address Designer's comment before this can merge."

assert_comment_present "$A7B_PR_NUM" "pr" "CHANGES REQUESTED"

# Verify: PR is NOT merged while blocked
assert_pr_state "$A7B_PR_NUM" "open"

# Dev iterates: fixes the design issue (simulated by adding a new commit)
git -C "$SANDBOX_WORK/.worktrees/$A7B_TASK_ID" commit --quiet --allow-empty \
  -m "fix(settings): replace hard-coded color with --color-interactive token"

git -C "$SANDBOX_WORK" push --quiet origin "$A7B_BRANCH"

# Designer re-reviews and posts "Design Approved"
e2e_add_comment "$A7B_PR_NUM" "pr" \
  "Design Approved — color token corrected. Responsive and accessible. Good to merge."

assert_comment_present "$A7B_PR_NUM" "pr" "Design Approved"

# Verify: "Design Approved" comment is now present (gate re-satisfied)
A7B_DESIGNER_APPROVED="$(jq -r --arg n "$A7B_PR_NUM" \
  '(.prs[$n].comments // []) | any(startswith("Design Approved")) | if . then "yes" else "no" end' \
  "$GH_STATE_FILE")"

if [[ "$A7B_DESIGNER_APPROVED" == "yes" ]]; then
  printf '  PASS  PR #%s has "Design Approved" after iteration — CR gate re-satisfied\n' "$A7B_PR_NUM"
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  PR #%s missing "Design Approved" after iteration\n' "$A7B_PR_NUM"
  FAIL=$(( FAIL + 1 ))
fi

# CR merges (gate satisfied after iteration)
e2e_add_comment "$A7B_PR_NUM" "pr" "LGTM — Design Approved (after iteration). Squash-merging."
assert_comment_present "$A7B_PR_NUM" "pr" "LGTM"

gh pr merge "$A7B_PR_NUM" --squash --delete-branch

assert_pr_state   "$A7B_PR_NUM" "merged"
assert_issue_closed "$A7B_BUG_NUM"

# INVARIANT: remote-branch-deleted (Path B)
assert_remote_branch_deleted "$A7B_BRANCH"  # INVARIANT: remote-branch-deleted

e2e_remove_worktree "$A7B_TASK_ID"
# INVARIANT: local-worktree-branch-deleted (Path B)
assert_worktree_removed "$A7B_TASK_ID"  # INVARIANT: local-worktree-branch-deleted
assert_branch_deleted   "$A7B_BRANCH"   # INVARIANT: local-worktree-branch-deleted


# ===========================================================================
# ARCHETYPE 8 — DevOps no-service repo (no-op deploy)
#
# Per devops-agent.md §COLD-START ANCHOR:
#   "If not (e.g., a docs/tooling-only repo): report 'No deployable services
#    in this project — DevOps is a no-op until a service ships.'"
#
# Per devops-agent.md §DEPLOY CURRENCY AUDIT:
#   "If the project has no deployable services, this section is a no-op —
#    skip it."
#
# Expected behaviour after a PR merges in a no-service repo:
#   1. No `deploy:*` labels appear on the PR.
#   2. DevOps posts a "no deployable surface" comment on the PR (per agent
#      contract §COLD-START ANCHOR — the "no deployable services" report),
#      OR no DevOps action occurs. The devops-agent.md contract says DevOps
#      REPORTS the no-service status; therefore a comment is the agent's
#      action here.
# ===========================================================================

e2e_reset_state

echo ""
echo "=========================================="
echo "  ARCHETYPE 8: DevOps no-service repo (no-op deploy)"
echo "=========================================="

# ---------------------------------------------------------------------------
# A8-1 — A normal chore PR merges (this repo is docs/tooling — no services)
# ---------------------------------------------------------------------------
echo ""
echo "--- A8 Stage 1: chore PR filed and merged ---"

A8_ISSUE_NUM="$(e2e_create_issue \
  "[CHORE] Update CLAUDE.md — add architecture section placeholder" \
  "Docs update. No deployable surface touched." \
  "enhancement,prioritized,priority:low")"

assert_label_present "prioritized" "$A8_ISSUE_NUM" "issue"
assert_issue_open    "$A8_ISSUE_NUM"

A8_BRANCH="chore/$A8_ISSUE_NUM-update-claude-md"
A8_TASK_ID="devops-noop-$A8_ISSUE_NUM"

e2e_create_worktree "$A8_TASK_ID" "$A8_BRANCH"
assert_worktree_exists "$A8_TASK_ID"
assert_branch_exists   "$A8_BRANCH"

git -C "$SANDBOX_WORK" push --quiet origin "$A8_BRANCH"

A8_PR_BODY="$(printf 'Add architecture section placeholder to CLAUDE.md.\n\nCloses #%s' "$A8_ISSUE_NUM")"
A8_PR_NUM="$(e2e_create_pr \
  "chore(docs): update CLAUDE.md — add architecture section placeholder" \
  "$A8_PR_BODY" \
  "$A8_BRANCH" \
  "main")"

e2e_add_label "$A8_PR_NUM" "pr" "in-review"

e2e_add_comment "$A8_PR_NUM" "pr" "LGTM — docs-only change."
assert_comment_present "$A8_PR_NUM" "pr" "LGTM"

gh pr merge "$A8_PR_NUM" --squash --delete-branch

assert_pr_state   "$A8_PR_NUM" "merged"
assert_issue_closed "$A8_ISSUE_NUM"

# INVARIANT: remote-branch-deleted
assert_remote_branch_deleted "$A8_BRANCH"  # INVARIANT: remote-branch-deleted

e2e_remove_worktree "$A8_TASK_ID"
# INVARIANT: local-worktree-branch-deleted
assert_worktree_removed "$A8_TASK_ID"  # INVARIANT: local-worktree-branch-deleted
assert_branch_deleted   "$A8_BRANCH"   # INVARIANT: local-worktree-branch-deleted

# ---------------------------------------------------------------------------
# A8-2 — DevOps no-op assertions
#
# After merge in a no-service repo:
#   1. No deploy:* labels on the PR (DevOps does not deploy).
#   2. DevOps posts a "no deployable surface" comment on the PR.
# ---------------------------------------------------------------------------
echo ""
echo "--- A8 Stage 2: DevOps no-op — no deploy labels, short-circuit comment ---"

# DevOps inspects the repo and recognises no deployable surface
# Per devops-agent.md: "If not ... report 'No deployable services in this
# project — DevOps is a no-op until a service ships.'"
e2e_add_comment "$A8_PR_NUM" "pr" \
  "No deployable surface — skipping deploy. This repo has no services. DevOps is a no-op until a service ships."

# Assert: "no deployable surface" comment posted by DevOps
assert_comment_present "$A8_PR_NUM" "pr" "no deployable surface"

# Assert: no deploy:* labels on the PR (DevOps never adds them for no-service repos)
# We check the three most common deploy label patterns
assert_label_absent "deploy:pending"    "$A8_PR_NUM" "pr"
assert_label_absent "deploy:in-flight"  "$A8_PR_NUM" "pr"
assert_label_absent "deploy:done"       "$A8_PR_NUM" "pr"


# ===========================================================================
# ARCHETYPE 9 — Cross-flow contract rejection by CR
#
# Per code-reviewer-agent.md §CROSS-FLOW CONTRACT ENFORCEMENT:
#   "If your project has shared contracts (schemas, API surfaces, IPC
#    protocols...) and the diff touches any of those: verify both sides
#    handle the change. A change to a schema that only updates one consumer
#    is a latent bug."
#
# Flow:
#   Dev opens PR that violates a shared contract (e.g. schema change without
#   updating the consumer) → CR detects → first CR comment has prefix
#   "CHANGES REQUESTED" → PR stays open → Dev fixes (pushes new commit) →
#   CR re-reviews → second CR comment has prefix "LGTM" → merge with
#   --delete-branch.
#
# Key assertions (per brief):
#   - First CR comment prefix == "CHANGES REQUESTED"
#   - After Dev's fix, second CR comment prefix == "LGTM"
#   - Final merge with --delete-branch: remote branch deleted + worktree cleaned
# ===========================================================================

e2e_reset_state

echo ""
echo "=========================================="
echo "  ARCHETYPE 9: Cross-flow contract rejection by CR"
echo "=========================================="

# ---------------------------------------------------------------------------
# A9-1 — Bug filed; Dev opens PR with cross-flow contract violation
#
# Scenario: Dev changed the auth token schema (added `expires_at` field)
# but only updated the auth service — forgot to update the client SDK.
# ---------------------------------------------------------------------------
echo ""
echo "--- A9 Stage 1: PR opened with cross-flow contract violation ---"

A9_ISSUE_NUM="$(e2e_create_issue \
  "[ENH] Add token expiry field to auth token schema" \
  "Auth token schema needs an expires_at field for client-side expiry checks." \
  "enhancement,prioritized,priority:medium")"

assert_label_present "prioritized" "$A9_ISSUE_NUM" "issue"
assert_issue_open    "$A9_ISSUE_NUM"

A9_BRANCH="feat/$A9_ISSUE_NUM-auth-token-expiry"
A9_TASK_ID="contract-violation-$A9_ISSUE_NUM"

e2e_create_worktree "$A9_TASK_ID" "$A9_BRANCH"
assert_worktree_exists "$A9_TASK_ID"
assert_branch_exists   "$A9_BRANCH"

git -C "$SANDBOX_WORK" push --quiet origin "$A9_BRANCH"

# Dev's PR touches the auth schema on the server side but does NOT update
# the client SDK — a classic cross-flow contract violation.
A9_PR_BODY="$(printf 'Add expires_at to auth token schema. Updates auth/schema.py only.\n\nCloses #%s' "$A9_ISSUE_NUM")"
A9_PR_NUM="$(e2e_create_pr \
  "feat(auth): add expires_at field to token schema" \
  "$A9_PR_BODY" \
  "$A9_BRANCH" \
  "main")"

e2e_add_label "$A9_ISSUE_NUM" "issue" "in-progress"
e2e_add_label "$A9_PR_NUM"    "pr"    "in-review"

assert_pr_state      "$A9_PR_NUM" "open"
assert_label_present "in-review"  "$A9_PR_NUM" "pr"

# ---------------------------------------------------------------------------
# A9-2 — CR detects contract violation → CHANGES REQUESTED
#
# Per code-reviewer-agent.md §CROSS-FLOW CONTRACT ENFORCEMENT and §Verdict:
# "Post one of three verdicts as a top-level PR comment with the verdict
#  as a prefix on its own line"
# ---------------------------------------------------------------------------
echo ""
echo "--- A9 Stage 2: CR detects contract violation → CHANGES REQUESTED ---"

A9_CR_FIRST_COMMENT="CHANGES REQUESTED — cross-flow contract violation: auth/schema.py adds expires_at but client/sdk/auth.ts still reads the old schema. Both consumers must be updated together. Update the SDK client type definitions before this can merge."

e2e_add_comment "$A9_PR_NUM" "pr" "$A9_CR_FIRST_COMMENT"

# First CR comment must have prefix "CHANGES REQUESTED" (per brief)
A9_FIRST_COMMENT_TEXT="$(jq -r --arg n "$A9_PR_NUM" \
  '(.prs[$n].comments // []) | .[0] // ""' \
  "$GH_STATE_FILE")"

if printf '%s' "$A9_FIRST_COMMENT_TEXT" | grep -q "^CHANGES REQUESTED"; then
  printf '  PASS  PR #%s first CR comment has prefix "CHANGES REQUESTED"\n' "$A9_PR_NUM"
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  PR #%s first CR comment does not start with "CHANGES REQUESTED"\n' "$A9_PR_NUM"
  FAIL=$(( FAIL + 1 ))
fi

# PR must still be open — CR did not merge
assert_pr_state "$A9_PR_NUM" "open"

# ---------------------------------------------------------------------------
# A9-3 — Dev pushes fix commit (updates both sides of the contract)
# ---------------------------------------------------------------------------
echo ""
echo "--- A9 Stage 3: Dev iterates — pushes fix commit (both sides updated) ---"

git -C "$SANDBOX_WORK/.worktrees/$A9_TASK_ID" commit --quiet --allow-empty \
  -m "fix(auth): update client/sdk/auth.ts to include expires_at field"

git -C "$SANDBOX_WORK" push --quiet origin "$A9_BRANCH"

# Dev comments to signal iteration complete
e2e_add_comment "$A9_PR_NUM" "pr" \
  "Fixed — client/sdk/auth.ts updated with expires_at field. Both auth/schema.py and client/sdk/auth.ts now in sync. Re-requesting review."

assert_comment_present "$A9_PR_NUM" "pr" "Fixed"

# ---------------------------------------------------------------------------
# A9-4 — CR re-reviews → LGTM
#
# After Dev pushes the fix, CR re-reviews and posts LGTM.
# Second CR comment must have prefix "LGTM" (per brief).
# ---------------------------------------------------------------------------
echo ""
echo "--- A9 Stage 4: CR re-reviews → LGTM ---"

A9_CR_SECOND_COMMENT="LGTM — both schema and client SDK updated. Contract violation resolved. Cross-flow contract now consistent."

e2e_add_comment "$A9_PR_NUM" "pr" "$A9_CR_SECOND_COMMENT"

# Second CR comment (index 2: 0=CR1, 1=Dev-fix, 2=CR2) must have prefix "LGTM"
A9_SECOND_CR_COMMENT_TEXT="$(jq -r --arg n "$A9_PR_NUM" \
  '(.prs[$n].comments // []) | .[2] // ""' \
  "$GH_STATE_FILE")"

if printf '%s' "$A9_SECOND_CR_COMMENT_TEXT" | grep -q "^LGTM"; then
  printf '  PASS  PR #%s second CR comment has prefix "LGTM" (after Dev fix)\n' "$A9_PR_NUM"
  PASS=$(( PASS + 1 ))
else
  printf '  FAIL  PR #%s second CR comment does not start with "LGTM"\n' "$A9_PR_NUM"
  FAIL=$(( FAIL + 1 ))
fi

assert_comment_present "$A9_PR_NUM" "pr" "LGTM"

# ---------------------------------------------------------------------------
# A9-5 — CR merges with --delete-branch
# ---------------------------------------------------------------------------
echo ""
echo "--- A9 Stage 5: CR merges with --delete-branch ---"

gh pr merge "$A9_PR_NUM" --squash --delete-branch

assert_pr_state  "$A9_PR_NUM" "merged"
assert_issue_closed "$A9_ISSUE_NUM"

# INVARIANT: remote-branch-deleted
assert_remote_branch_deleted "$A9_BRANCH"  # INVARIANT: remote-branch-deleted

e2e_remove_worktree "$A9_TASK_ID"
# INVARIANT: local-worktree-branch-deleted
assert_worktree_removed "$A9_TASK_ID"  # INVARIANT: local-worktree-branch-deleted
assert_branch_deleted   "$A9_BRANCH"   # INVARIANT: local-worktree-branch-deleted

# ===========================================================================
print_summary
