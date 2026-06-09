# Design: SDLC E2E Test Suite

## Context

The SDLC is enforced by written contracts (`SDLC.md`, agent `.md` files) and six mechanical hooks. No test verifies full workflow correctness: that the label state transitions, branch/worktree lifecycle, PR body discipline, and post-merge cleanup all behave correctly end-to-end.

PRD: `docs/prd/PRD-sdlc-e2e-test-suite.md`
Umbrella issue: #65
Slice 1 issue: #67 — harness infrastructure only; no archetype tests yet.

## Approach

Option A from the PRD: hermetic Bash + sandbox git repo + fake `gh` stub. No network, no GitHub credentials required.

Three deliverables:

1. `tests/lib_e2e.sh` — harness library with sandbox lifecycle management and the assertion helper API.
2. `tests/fixtures/fake-gh.sh` — `gh` CLI stub that persists state to a JSON file.
3. `tests/test_e2e_smoke.sh` — smoke test that exercises harness setup/teardown with no archetype logic.

`tests/run.sh` already auto-discovers `tests/test_*.sh`; naming the smoke test `test_e2e_smoke.sh` automatically integrates it.

## Sandbox repo layout

```
$SANDBOX_ROOT/                  # mktemp -d; trap 'rm -rf "$SANDBOX_ROOT"' EXIT
  repo/                         # git init --bare  (the "remote origin")
  work/                         # git clone $SANDBOX_ROOT/repo (the working clone)
    .git/
    .worktrees/                 # git worktrees added here per archetype
      <task-id>/                # feature branch worktree
  gh-state.json                 # fake gh stub state file (see below)
  bin/                          # contains fake-gh.sh symlinked as "gh"
```

### Why a bare repo as "origin"

A bare repo at `$SANDBOX_ROOT/repo` acts as the remote. The working clone at `$SANDBOX_ROOT/work` operates like a real developer checkout. Worktrees added inside `$SANDBOX_ROOT/work/.worktrees/` mirror the real project layout exactly, so assertions about `.worktrees/<task-id>` existence are structurally equivalent to the real invariant.

### Trap cleanup

Every test file that sources `lib_e2e.sh` calls `e2e_setup` which:

1. Creates `SANDBOX_ROOT` with `mktemp -d`.
2. Registers `trap 'e2e_teardown' EXIT INT TERM` immediately — so cleanup fires even if the test aborts mid-run.
3. Exports `SANDBOX_ROOT`, `SANDBOX_REPO`, `SANDBOX_WORK`, and `GH_STATE_FILE` for use by helper functions.
4. Prepends `$SANDBOX_ROOT/bin` to `PATH` so `gh` resolves to the stub.

`e2e_teardown` calls `rm -rf "$SANDBOX_ROOT"`. No leaks survive the process boundary.

## Fake `gh` state schema

State is persisted to `$GH_STATE_FILE` (a JSON file in `$SANDBOX_ROOT`). The stub reads and writes this file atomically (read → modify in jq → write back).

### Top-level shape

```json
{
  "issues": {
    "<number>": {
      "number": 1,
      "title": "string",
      "body": "string",
      "state": "open | closed",
      "labels": ["label1", "label2"],
      "comments": ["comment text", ...]
    }
  },
  "prs": {
    "<number>": {
      "number": 10,
      "title": "string",
      "body": "string",
      "state": "open | merged | closed",
      "head_branch": "feat/67-slug",
      "base_branch": "main",
      "labels": ["in-review"],
      "comments": ["LGTM — ..."],
      "merged_at": "2026-05-22T00:00:00Z | null"
    }
  },
  "next_issue_number": 2,
  "next_pr_number": 11
}
```

### Auto-increment counters

`next_issue_number` and `next_pr_number` start at 1 and are incremented on each `gh issue create` / `gh pr create`. This mirrors real GitHub behavior (monotonically increasing IDs).

### `Closes #N` auto-close simulation

On `gh pr merge <N> --squash --delete-branch`, the stub:

1. Reads the PR body from `prs.<N>.body`.
2. Scans for all `Closes #<num>` tokens (case-insensitive, whitespace-tolerant regex).
3. For each matched issue number: sets `issues.<num>.state = "closed"`.
4. Sets `prs.<N>.state = "merged"` and `prs.<N>.merged_at` to a fixed timestamp.
5. Deletes the remote-tracking ref: `git -C "$SANDBOX_WORK" push origin --delete "<head_branch>"`.

`Refs #N` tokens are NOT auto-closed (correct — they are tracking references only).

### `--delete-branch` behavior

The stub does NOT simulate Hook 6 enforcement. Hook 6 is a PreToolUse hook on `gh pr merge` — it fires before the command reaches the stub. The E2E tests that exercise full-pipeline assertions will call hooks directly via `run_case` from `lib.sh` as a pre-assertion step, then call the stub directly to simulate the merge state transition.

The stub's `gh pr merge` DOES simulate the branch deletion: it calls
`git -C "$SANDBOX_WORK" push origin --delete "<head_branch>"` unconditionally when merging, because by the time the stub is called, Hook 6 has already verified the flag is present.

## Assertion helper API

All helpers are defined in `tests/lib_e2e.sh`. They follow the same pass/fail accounting pattern as `lib.sh` (`PASS` / `FAIL` counters, `print_summary`). Helpers are designed to be composed — a single archetype test calls several helpers in sequence to assert full state transitions.

### Sandbox lifecycle

```bash
e2e_setup
# Creates SANDBOX_ROOT, bare repo, working clone, gh-state.json, bin/gh symlink.
# Traps teardown on EXIT. Must be called once per test file, before any other helper.

e2e_teardown
# Removes SANDBOX_ROOT entirely. Called by trap — tests should not call directly.

e2e_reset_state
# Writes a fresh empty gh-state.json. Useful for multi-scenario test files that
# reuse the same sandbox (worktrees/branches are NOT reset — call e2e_setup for full isolation).
```

### Issue helpers

```bash
e2e_create_issue <title> <body> <labels_csv>
# Creates an issue via fake gh. Prints the new issue number.

e2e_add_label <issue_or_pr_num> <type> <label>
# Adds label to an issue (type="issue") or PR (type="pr").
# Wraps: gh issue edit --add-label / gh pr edit --add-label

e2e_remove_label <issue_or_pr_num> <type> <label>
# Removes label from an issue or PR.

e2e_close_issue <issue_num>
# Marks issue closed in stub state (direct state mutation, not via PR body).
```

### PR helpers

```bash
e2e_create_pr <title> <body> <head_branch> <base_branch>
# Creates a PR via fake gh. Prints the new PR number.
# Automatically picks up the labels from the issue referenced by Closes #N in body.

e2e_merge_pr <pr_num>
# Calls: gh pr merge <pr_num> --squash --delete-branch (via the stub directly).
# Simulates: PR state → merged, Closes #N → issue closed, remote branch deleted.
# Does NOT enforce Hook 6 (hook enforcement tested separately in test_hooks.sh).

e2e_add_comment <issue_or_pr_num> <type> <comment_text>
# Appends a comment to the stub state for an issue or PR.
```

### Worktree helpers

```bash
e2e_create_worktree <task_id> <branch_name>
# Runs: git -C "$SANDBOX_WORK" worktree add .worktrees/<task_id> -b <branch_name>
# Creates the branch in the sandbox repo.

e2e_remove_worktree <task_id>
# Runs: git -C "$SANDBOX_WORK" worktree remove .worktrees/<task_id>
# Deletes the local branch after removing the worktree.
```

### Assertion helpers

```bash
assert_label_present <label> <label> <issue_or_pr_num> <type>
# PASS if <label> is in the stub state's label array for the item.
# type: "issue" | "pr"
# Example: assert_label_present "in-progress" 42 "issue"

assert_label_absent <label> <issue_or_pr_num> <type>
# PASS if <label> is NOT in the stub state's label array.

assert_issue_open <issue_num>
# PASS if issue state == "open".

assert_issue_closed <issue_num>
# PASS if issue state == "closed".

assert_pr_state <pr_num> <expected_state>
# PASS if PR state == expected_state. Valid states: "open", "merged", "closed".

assert_worktree_exists <task_id>
# PASS if directory $SANDBOX_WORK/.worktrees/<task_id> exists.

assert_worktree_removed <task_id>
# PASS if directory $SANDBOX_WORK/.worktrees/<task_id> does NOT exist.

assert_branch_exists <branch_name>
# PASS if the branch exists locally in $SANDBOX_WORK.

assert_branch_deleted <branch_name>
# PASS if the branch does NOT exist locally in $SANDBOX_WORK.

assert_remote_branch_deleted <branch_name>
# PASS if the branch does NOT exist in origin (the bare repo at $SANDBOX_REPO).

assert_pr_body_contains <pr_num> <substring>
# PASS if the PR body contains <substring>. Used to verify Closes #N discipline.

assert_comment_present <issue_or_pr_num> <type> <substring>
# PASS if any comment on the item contains <substring>.
```

## Stub wiring

The stub is wired via `PATH` manipulation — `e2e_setup` creates `$SANDBOX_ROOT/bin/gh` as a symlink (or wrapper script) pointing to `tests/fixtures/fake-gh.sh`. Prepending `$SANDBOX_ROOT/bin` to `PATH` means all `gh` invocations in the test process and its children resolve to the stub, not the real `gh` binary.

This approach is preferred over function overrides because:
1. Shell functions don't propagate reliably through `bash -c` subshells (the same reason `gh-labels-stub.sh` exists as a script file, not an exported function — documented in `tests/fixtures/gh-labels-stub.sh`).
2. PATH shadowing is transparent to any subprocess the test spawns.
3. It does not require modifying the hook scripts.

The stub reads `GH_STATE_FILE` from the environment. `e2e_setup` exports it. Hook scripts that need the stub for label lookups (Hook 3's `CLAUDE_HOOK_GH_LABELS_CMD` pattern) can use `fake-gh.sh pr view <N> --json labels --jq '[.labels[].name]'` directly.

## Hook integration in sandbox

Hooks fire as PreToolUse handlers in Claude Code — they are NOT invoked when Bash runs `gh pr merge` directly in a test process. The sandbox does not replicate the Claude Code hook invocation machinery.

E2E tests that verify hook-level invariants use `run_case` from `lib.sh` — the same pattern as `test_hooks.sh`. This keeps hook behavior tested at the unit level (direct JSON payload → hook exit code) and keeps the E2E layer focused on state machine transitions (label state, worktree existence, branch cleanup).

For Slice 2's worktree-cleanup assertion (Archetype 1), the E2E test will:
1. Use `run_case` to verify Hook 3 would allow the merge (PR has `in-review`).
2. Use `run_case` to verify Hook 6 would allow the merge (`--delete-branch` present in the simulated command).
3. Call `e2e_merge_pr` to execute the state transition.
4. Assert post-merge state: `assert_worktree_removed`, `assert_branch_deleted`, `assert_remote_branch_deleted`, `assert_issue_closed`.

Hook 6 is the relevant hook for Slice 2's worktree-cleanup assertion. It enforces `--delete-branch` at command time; the E2E assertion verifies the downstream effect (worktree actually gone).

## Tests

Slice 1 ships `tests/test_e2e_smoke.sh`:
- `e2e_setup` succeeds (sandbox root created, git repos initialized).
- Fake `gh issue create` returns a number and persists to state.
- Fake `gh issue edit --add-label` adds the label; `assert_label_present` passes.
- Fake `gh pr create` returns a number.
- Fake `gh pr merge --squash --delete-branch` transitions PR to merged; `Closes #N` auto-closes issue.
- `assert_issue_closed` passes.
- `assert_worktree_removed` passes after `e2e_remove_worktree`.
- `assert_remote_branch_deleted` passes after merge.
- Teardown leaves no temp directories behind (verified by checking `$SANDBOX_ROOT` no longer exists after test exits).

Slices 2–5 will add `tests/test_e2e_archetype_*.sh` files, each sourcing `lib_e2e.sh` and running one or more archetype scenarios.

## Risks

- **Stub drift**: `fake-gh.sh` emulates real `gh` output. If `gh` CLI changes its JSON schema for `gh pr view`, the stub may diverge. Mitigation: `tests/test_e2e_smoke.sh` exercises every stub subcommand and will catch output-format failures immediately. Long-term: a contract test (`test_stub_contract.sh`) can diff stub output against a pinned real-`gh` snapshot.
- **PATH isolation**: tests must not accidentally call real `gh` (which would fail in CI without credentials). Mitigation: `e2e_setup` prepends the stub bin; `fake-gh.sh` emits a recognizable sentinel in its header that the smoke test can grep for.
- **Branch/worktree state between test scenarios**: if a test file runs multiple scenarios and shares the same sandbox, leftover branches cause `git worktree add` to fail. Mitigation: each archetype test creates unique branch names (using the scenario number as a suffix), or calls `e2e_setup` once per scenario.

## Out of scope

- Real GitHub API calls (Option B from PRD).
- Hook 7 local-worktree cleanup enforcement (separate child issue).
- Designer-gate enforcement hook (separate child issue).
- Archetype tests (Slices 2–5).
- CI YAML changes.
