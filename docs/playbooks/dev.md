# Dev Agent Playbook

Project-specific notes that future-you (the Dev agent on this project) needs. Append a section when you learn something worth keeping; delete sections that go stale. Keep this readable end-to-end.

> **Promote-to-skill:** when a procedure here shows up in another agent's playbook too, or you've done it the same way 3+ times, lift it into a shared skill at `.claude/skills/<name>/SKILL.md`. See the `skill-maintenance` skill for the authoring pattern.

## Hook development gotchas

### Hook triggers block your own commands (including commits and PR creation)

The hooks run on every Bash tool call, including the tool calls used to test,
commit, and open PRs. If your commit message or PR body contains a phrase that
triggers a hook, the hook blocks the tool call itself.

**Workarounds:**
- Rephrase commit messages to avoid trigger tokens (e.g., describe "gh pr merge"
  as "the merge subcommand" rather than writing the literal phrase).
- Use `--body-file /tmp/body.md` for `gh pr create` when the PR body would
  contain trigger phrases (this is what code-reviewer-agent had to do in PR #26,
  and what motivated bug #28).
- Never use `CLAUDE_HOOK_BYPASS=1` to work around during normal dev — it disables
  ALL hooks. Only use for genuine ops emergencies.

### Writing hook regex: require command-position, not substring match

When a hook detects a command pattern, always require the pattern to appear at
the start of the command string OR after a shell separator (`; && || |`).
Scanning the full command string causes false positives when the pattern appears
inside a quoted argument (e.g., `grep "gh pr merge" SDLC.md` being blocked by
the merge hook).

Correct pattern (anchored to shell segment start):
```
(^|;|&&|\|\||[|])[[:space:]]*gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)
```

Wrong (matches anywhere including inside quoted args):
```
\bgh[[:space:]]+pr[[:space:]]+merge\b
```

### Testing hooks locally without CLAUDE_HOOK_BYPASS

The test harness (`bash tests/run.sh`) pipes JSON payloads directly to hook
scripts, bypassing Claude Code's hook registration. Use this to verify hooks
work correctly. Do NOT try to pipe payloads interactively when those payloads
contain trigger phrases — Claude Code intercepts the tool call first.

### Hook tests that read real git state must use an env-var override

Hooks that call `git symbolic-ref --short HEAD` or similar at test time are
flaky: the result depends on which branch the test runner is checked out on.

Pattern: add an env-var override (e.g. `CLAUDE_HOOK_TEST_BRANCH`) that short-
circuits the git call. Set it in the test invocation; never rely on real git
state inside a test. Hook 1 uses this pattern; Hook 4 uses the analogous
`CLAUDE_HOOK_TEST_ROOT` for filesystem checks.

```bash
# Hermetic — branch is explicit, not read from git
CLAUDE_HOOK_TEST_BRANCH=feat/test run_case "$HOOK" "..." "git commit -m fix" "allow"
CLAUDE_HOOK_TEST_BRANCH=main      run_case "$HOOK" "..." "git commit -m fix" "block"
```

Hook 4's sync check (added in #45) uses the analogous `CLAUDE_HOOK_TEST_SYNC` to
avoid real `git fetch` calls during tests. Three sentinel values:

```bash
CLAUDE_HOOK_TEST_SYNC=behind:5    # simulate 5 commits behind
CLAUDE_HOOK_TEST_SYNC=ok          # simulate up to date (silent)
CLAUDE_HOOK_TEST_SYNC=fetch-failed # simulate offline / no network
```

### Hooks that call git must guard against non-git directories

Hook code that runs `git -C "$REPO_ROOT" <cmd>` will fail if `REPO_ROOT` is a
temp directory used by tests (not a real git repo). Always guard with:

```bash
if git -C "$REPO_ROOT" rev-parse --git-dir &>/dev/null; then
  # ... git calls here
fi
```

Without this guard, test cases that point `--test-root` at a temp dir will see
unexpected output (e.g. "offline" info note) and fail.

## E2E harness gotchas (lib_e2e.sh / fake-gh.sh)

### fake-gh.sh stores labels as plain strings; output normalizes to objects

The stub's internal state stores labels as `["bug","in-progress"]` (array of
strings). When outputting via `--json labels`, the stub normalizes them to
`[{"name":"bug",...}]` format (matching real `gh`). Assertion helpers in
`lib_e2e.sh` read from the state file directly and use the string format.

**Consequence:** test assertions against stub state (e.g., `assert_label_present`)
work with plain string label names. Tests that call `gh ... --json labels --jq
'[.labels[].name]'` work because normalization happens in `_apply_jq_output`.
Don't mix the two: don't call `jq '.labels[].name'` directly on state file values.

### Cannot delete a local branch while a worktree is checked out on it

`git branch -D <branch>` fails if a worktree is currently on that branch. The
correct cleanup order after merge:
1. `e2e_remove_worktree <task_id>` — removes the worktree directory AND deletes
   the local branch (in that order).
2. `assert_branch_deleted <branch>` — now passes.

`e2e_merge_pr` only deletes the REMOTE branch (mirrors real `gh pr merge`
behavior). Local branch cleanup is a separate step.

### `jq -r` does not compact-format arrays/objects

`jq -r` only strips quotes from string values. Arrays and objects are still
pretty-printed (multi-line). When asserting on JSON array/object output, compare
via `| jq -c .` to get compact single-line form, or use `assert_eq` with a
compact-JSON expected string.

### Each test file must call `e2e_setup` once and then `print_summary` at the end

`e2e_setup` registers the EXIT trap for teardown. If a test file sources
`lib_e2e.sh` but doesn't call `e2e_setup`, the teardown trap is never registered
and sandbox directories will leak. Always the first call in a test file.

### `local` keyword is only valid inside bash functions

The stub script (`fake-gh.sh`) runs at top level (not inside functions).
Using `local varname` at top level produces "local: can only be used in a
function" and the variable is never set. Use plain `varname=""` for top-level
variable declarations in the stub.

## PostToolUse hooks: env var inheritance

When writing a `PostToolUse` hook, inline env var assignment (`VAR=val cmd`) only
applies to the FIRST command in a pipeline. If the hook receives its payload via
stdin pipe, use `env VAR=val bash script < payload_file` instead, or `export` the
vars before the pipeline.

Wrong pattern in tests (env doesn't reach bash script):
```bash
CLAUDE_HOOK_TEST_GH_BRANCH_CMD="$stub" printf '%s' "$payload" | bash hook.sh
```

Correct pattern:
```bash
printf '%s' "$payload" > /tmp/payload.json
env CLAUDE_HOOK_TEST_GH_BRANCH_CMD="$stub" bash hook.sh < /tmp/payload.json
```

## macOS symlink paths in git worktree list

`git worktree list --porcelain` returns resolved paths (e.g. `/private/var/...`)
while `mktemp` and `realpath` may return the unresolved path (`/var/...`). Always
canonicalize WORKTREES_DIR with `cd "$dir" && pwd -P` before comparing against
paths returned by git commands on macOS.

## PostToolUse hooks do NOT fire in agent sub-sessions

`settings.json` hooks (PreToolUse / PostToolUse) only fire when the OPERATOR'S
main session executes a tool. When any specialist agent (CR, Dev, etc.) runs
inside an agent sub-session (spawned via the `Agent` tool), ALL hook dispatch
is bypassed — confirmed bug: anthropics/claude-code #34692 (March 2026).

**Consequence for hook design:** Don't rely on PostToolUse hooks for enforcement
that must work in agent-driven workflows. Use an explicit wrapper script instead.
See `bin/merge-pr.sh` as the canonical pattern (PR #84).

## PostToolUse shell hook stdin fields (real runtime — corrected in PR #84)

The Claude Code runtime sends these fields for Bash `PostToolUse`:
- `tool_response.stdout` — the command's stdout
- `tool_response.stderr` — the command's stderr
- `tool_response.exit_code` — the command's exit code (int)

NOT `tool_response.output` / `tool_response.error` as originally documented.
When writing hooks that read tool_response, use the correct field names. For
backward compat with old test payloads, use `// .tool_response.error` fallback.

## gh pr merge exits 1 for local branch checkout conflicts

`gh pr merge <N> --squash --delete-branch` returns exit code 1 when the
GitHub merge succeeded but the local branch cannot be deleted because a
worktree still has it checked out:
  "error: Cannot delete branch '<branch>' checked out at '<path>'"

In this case the merge on GitHub was real. Any hook or script that bails on
non-zero exit alone will miss the cleanup. Only skip cleanup when a known
merge-failure phrase is in stderr AND exit code is non-zero.
