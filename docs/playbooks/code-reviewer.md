# Code Reviewer Agent Playbook

Project-specific notes that future-you (the Code Reviewer agent on this project) needs. Append a section when you learn something worth keeping; delete sections that go stale. Keep this readable end-to-end.

> **Promote-to-skill:** when a procedure here shows up in another agent's playbook too, or you've done it the same way 3+ times, lift it into a shared skill at `.claude/skills/<name>/SKILL.md`. See the `skill-maintenance` skill for the authoring pattern.

## GitHub Actions — markdownlint-cli2-action config input

`DavidAnson/markdownlint-cli2-action` takes a **file path** in its `config:` input, not an inline JSON blob. Passing raw JSON causes the action to treat the JSON text as a filename and fail immediately with "File name should be (or end with) one of the supported types." The fix is to commit a `.markdownlint.json` (or `.markdownlint-cli2.jsonc`) file and pass its path, or to use `npx markdownlint-cli2` in a `run:` step and write the config inline there. Seen in PR #15.

## actions/checkout Node.js 20 deprecation

As of mid-2025 `actions/checkout@v4` emits Node.js 20 deprecation warnings on every run. The runner will force Node.js 24 in June 2026 and remove Node.js 20 in September 2026. Flag this as a non-blocking finding on any PR that uses `@v4`; recommend upgrading to `@v5`. Not a merge blocker today.

## Hook self-test harness — jq vs printf for JSON construction

When a bash self-test builds a JSON payload by interpolating a command string, `printf '{"command":"%s"}' "$cmd"` produces invalid JSON whenever `$cmd` contains literal double-quote characters. Use `jq -cn --arg cmd "$cmd" '{"tool_input":{"command":$cmd}}'` instead — jq properly escapes the quotes. The printf approach causes silent false-green tests (jq parse error → COMMAND="" → hook exits 0 → test reports "allow" when the hook would have blocked the real command). Seen in PR #17.

## Hook argument-list tokenizer — quote stripping for shell-quoted tokens

When a PreToolUse hook tokenizes push arguments with `for token in $PUSH_ARGS`, bash word-splits on IFS but does NOT strip shell quote characters. The token for `'origin'` is the five-character string `'origin'`, not `origin`. Strip matching outer single or double quote pairs from each token before comparison (`token="${token:1:${#token}-2}"` when the token matches `\'*\'` or `"*"`). Do not use `eval` — Option A (explicit strip) is safe and predictable. Seen in PR #17 Fix 2 / commit 81d300d.

## Hook edge cases that are non-blocking for no-direct-push-main.sh

These forms allow through and are acceptable — document rather than require fixes:
- Command substitution in the command string (`git push \`echo origin\` main`, `git push $(echo origin) main`): jq passes the literal text; backticks/dollar-parens are not shell-expanded in jq context. The remote token does not equal `origin`.
- Shell variables (`git push $REMOTE main`): same reasoning — literal `$REMOTE` does not equal `origin`.
- Unmatched quotes (`git push 'origin main`): malformed shell syntax; the shell rejects this at execution before the push runs. Consistent with fail-open design.
- Nested quotes (`git push "'origin'" "'main'"`): outer pair stripped → `'origin'` != `origin`, loop breaks. Non-exploitable; git would error on remote name `'origin'`.
- All of these require deliberate self-evasion; the escape hatch is `CLAUDE_HOOK_BYPASS=1`.

## Hook false-positive — phrase-in-argument pattern (Hook 6, potentially Hook 3)

Any hook that uses `grep -qE '\bgh[[:space:]]+pr[[:space:]]+merge\b'` (or similar adjacent-token regex) on the raw COMMAND string will false-positive when that phrase appears inside a quoted argument of an unrelated command. For example, a `gh pr comment` whose body contains the literal text matching the regex will be blocked.

**Workaround at review time:** write the comment/body to a temp file and pass `--body-file /tmp/file.txt` to `gh pr comment` and `gh issue create`. This keeps the phrase out of the shell command string that the hook inspects.

**Long-term fix pattern (from issue #28):** strip quoted strings from COMMAND before the detection grep, or check that the token sequence appears as an actual command (at position 0 or after a shell separator). See issue #27 (Hook 3) and issue #28 (Hook 6) for the exact sed-based fix.

**When posting LGTM verdicts on PRs that discuss hooks:** always use `--body-file` — never inline the body as a `--body` argument if the body references hook command examples.

## Worktree blocks local branch deletion at merge time

`gh pr merge <N> --squash --delete-branch` always succeeds on the remote (PR merged, remote branch deleted) but exits non-zero when a local worktree has the branch checked out:

```
failed to delete local branch <branch>: failed to run git: error: Cannot delete branch '<branch>' checked out at '.worktrees/<task-id>'
```

This is not a merge failure — verify with `gh pr view <N> --json state,mergedAt,mergeCommit`. The PR is MERGED and the remote branch is gone. The lingering local worktree is a Dev-session cleanup concern; the Dev agent that created the worktree should `git worktree remove .worktrees/<task-id>` after their session ends. Not a merge blocker. Seen on PRs #50, #51, #52 (issue #48 drain, May 2026).

## Missing in-review label — Hook 3 blocks merge

Hook 3 (`pr-merge-requires-in-review.sh`) blocks `gh pr merge <N>` when the PR lacks the `in-review` label. Hook 2 (`restricted-label-ownership.sh`) also blocks the code-reviewer-agent from applying `in-review` (Dev-only label). If a Dev session opens a PR without applying `in-review`, the merge is doubly gated. Remediation options in priority order:

1. Operator applies `in-review` directly (`gh pr edit <N> --add-label in-review` as operator — SDLC allows operator override of any label).
2. Route back to the Dev session: `gh pr edit <N> --add-label in-review`.
3. Ops emergency bypass: `CLAUDE_HOOK_BYPASS=1` (document reason).

Do NOT bypass silently — surface to operator and let them choose. Seen on PR #49 (issue #47, May 2026).

## POSIX ERE bracket expression vs alternation — hook regex trap

In POSIX ERE, `[[:space:]|$]` is a bracket expression where `|` and `$` are **literal characters**, not alternation or end-of-line anchors. The correct form to mean "whitespace OR end-of-line" is `([[:space:]]|$)`. The two look visually similar but behave differently:

- `[[:space:]|$]` — matches one character that is whitespace, literal `|`, or literal `$`
- `([[:space:]]|$)` — matches either one whitespace character, or the end of the string/line

When reviewing hook regexes that include a trailing boundary after the command token (e.g., after `merge`), verify the correct alternation form is used. A bracket expression will miss the case where `merge` appears at absolute end-of-string with no trailing character — which is an edge case in practice, but the playbook example and the hook code must agree. Seen in PR #30: both hooks used `[[:space:]|$]` while the playbook documented `([[:space:]]|$)`.

## Hook 6 — `--delete-branch` missed when flag is semicolon-adjacent

Hook 6's token walk (`for token in $MERGE_SEGMENT`) splits on IFS whitespace. When the merge command is part of a compound command with no space before the semicolon — `gh pr merge N --squash --delete-branch; CMD2` — the token is `--delete-branch;` (with trailing semicolon), which does not equal `--delete-branch`. Hook 6 then (incorrectly) blocks the merge.

**Workaround:** always issue `gh pr merge` as a standalone command, not chained in a compound statement. Seen during PR #53 merge (May 2026). A hook fix (strip trailing semicolons from each token before comparison) is the long-term solution — file a follow-up issue if this recurs.

## bin/merge-pr.sh Tier 3 test isolation gap — Test 16 makes a real gh API call

`test_hooks.sh` Test 16 (failed merge stub, cleanup skipped) does NOT set `CLAUDE_HOOK_TEST_PR_STATE_CMD`. When the Tier 3 branch executes, it falls through to the real `gh pr view 99 --json state` call. Since PR 99 doesn't exist, `gh` errors out, the `|| true` catches it, `PR_STATE` is empty, and cleanup is correctly skipped. Test result is correct. However, this means Test 16 makes a live network call in the test suite. Non-blocking, but if the network is unavailable or GH auth is not set, Test 16's Tier 3 path may behave differently (still passes because empty != "MERGED", but worth knowing). Seen during PR #88 review (May 2026).
