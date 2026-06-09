---
description: Sync, run tests, push, open a PR. Manual fallback for the Dev → CR loop.
---

# Ship

Adapted from [garrytan/gstack](https://github.com/garrytan/gstack)'s `/ship` — used and credited under MIT license.

End-to-end push-to-PR flow. Use when you're working solo (no Dev Agent in the loop) or when you want to package up the current worktree's changes into a reviewable PR without spawning the agent team.

## Pre-flight

1. **Confirm you're in a worktree** (not the primary repo path). If you're in the primary path, abort:

   ```bash
   pwd | grep -q ".worktrees/" || echo "ERROR: not in a worktree — run git worktree add first"
   ```

2. **Confirm you're on the right branch:**

   ```bash
   git branch --show-current
   ```

   Expected pattern: `<type>/<issue-num>-<slug>` per `SDLC.md`. If wrong, fix before proceeding.

3. **Sync with origin:**

   ```bash
   git fetch origin
   git rebase origin/<default-branch>
   ```

   If rebase has conflicts: stop, resolve, continue. Do not force-push to shared branches.

## Build + verify

4. **Run the test suite.** Use the project's test command from `CLAUDE.md` (Common commands section).

   ```bash
   <test-command>
   ```

   If tests fail: stop. Don't push broken tests.

5. **Run lint / format / type check** if the project has them:

   ```bash
   <lint-command>
   <typecheck-command>
   ```

6. **For UI changes:** start the dev server, exercise the feature in a browser. Capture a screenshot if it's visual.

## Coverage audit

7. **Check for missing tests** on the diff:

   ```bash
   git diff origin/<default-branch>..HEAD --stat
   ```

   For each changed source file, is there a corresponding test file? If you added a new code path without a test, write the test now (Boil the Lake — tests are the cheapest lake to boil).

## Commit + push

8. **Verify commit messages** follow `<type>(<scope>): <summary>` per SDLC. Re-message if needed (`git commit --amend` for the last commit; interactive rebase only for unpushed commits).

9. **Push:**

   ```bash
   git push -u origin <branch-name>
   ```

## Open the PR

10. **Draft the PR body** with the test plan:

    ```bash
    gh pr create --title "<type>(<scope>): <summary>" --body "$(cat <<'EOF'
## Summary
<1-3 bullets — what changed and why>

## Test plan
- [ ] <how reviewer can verify this works>
- [ ] <edge case 1>
- [ ] <edge case 2>

## Notes / risks
<anything reviewer should pay extra attention to; flag any cross-flow contract touch points>

Closes #<N>
EOF
)"
    ```

11. **Apply `in-review` label:**

    ```bash
    gh pr edit <PR-N> --add-label in-review
    ```

12. **If your project uses a Code Reviewer Agent:** the `in-review` label is the trigger. Otherwise, request review from a human reviewer.

## Report

13. **Print a one-line summary** of what shipped + the PR URL.

```
Shipped: <type>(<scope>): <summary>
PR: <URL>
Test plan: <N> items, all checked
```

## When ship fails

- **Tests fail:** debug locally, push the fix, retry from step 4. Don't push red tests.
- **Lint fails:** auto-fix if the tool supports it; otherwise hand-fix. Don't skip.
- **Rebase conflicts:** resolve them; don't `--theirs` or `--ours` your way out without understanding what you're discarding.
- **Push rejected (branch protection):** read the branch protection rules; usually means CI needs to pass first, or you need a reviewer assigned.

## Anti-patterns

- **Pushing without running tests.** "CI will catch it" — except CI catches what CI tests for, and reviewer time is valuable.
- **Force-pushing to a shared branch.** Only force-push to your own feature branches, and only when nobody else is reviewing.
- **PR body without a test plan.** That's the reviewer's checklist; without it they re-derive the test plan from scratch.
- **`Closes #N` on a slice.** If this PR is one of several for issue #N, use `Refs #N`. Only the final slice uses `Closes`.
