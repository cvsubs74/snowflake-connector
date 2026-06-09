---
name: worktree-management
description: "How specialist agents create, use, and clean up git worktrees so parallel sessions never conflict."
---

# Worktree Management

Every specialist session creates its own [git worktree](https://git-scm.com/docs/git-worktree) before doing branch work. This is non-negotiable: it prevents the most common failure mode of parallel agent sessions — two specialists editing the same files in the primary repo path and clobbering each other.

---

## The rules

1. **Never edit in the primary repo path** (the path the operator ran `claude` in). That path may be on whoever's branch.
2. **Never reuse another session's worktree.** Each session creates its own under `.worktrees/<task-id>` (or `.claude/worktrees/<task-id>` if the project prefers that path — pick one convention per project).
3. **Prune after merge** — leftover worktrees consume disk and add visual noise to `git worktree list`.
4. **One worktree per branch.** Don't try to share a worktree across two branches "to save time" — that's how you get cross-branch contamination.

---

## Create a worktree

```bash
# From the primary repo path:
git fetch origin
git worktree add .worktrees/<task-id> -b <branch-name> origin/<default-branch>
cd .worktrees/<task-id>
```

Replace:

- `<task-id>` — typically the issue number, optionally with a slug. e.g. `123-validation-overflow`.
- `<branch-name>` — your branch per the SDLC convention. e.g. `fix/123-validation-overflow`.
- `<default-branch>` — your repo's default (usually `main`).

---

## Work inside the worktree

Treat it as if it were the primary repo:

```bash
cd .worktrees/<task-id>

# Edit files, run tests, commit, push:
<your edits>
<your test command>
git add <files>
git commit -m "<message>"
git push -u origin <branch-name>
gh pr create ...
```

Tools that need to be run from the repo root (test runners, build scripts, dev servers) run from inside this worktree path — that's the whole point.

---

## Clean up after merge

When your PR merges, prune the worktree:

```bash
# From the primary repo path:
git worktree remove .worktrees/<task-id>

# If your local branch is no longer needed (already merged on remote):
git branch -D <branch-name>
```

If you abandoned the work (didn't open or didn't merge a PR), still prune:

```bash
git worktree remove .worktrees/<task-id> --force
```

---

## Avoiding collisions across parallel sessions

When multiple specialist sessions are active:

- Each gets its own worktree path. Two Dev sessions on issues #100 and #101 use `.worktrees/100-<slug>` and `.worktrees/101-<slug>`.
- Two Dev sessions on the SAME issue (rare; usually a coordination failure) MUST agree on scope boundaries first or serialize. If unavoidable, use `.worktrees/100a-<slug>` and `.worktrees/100b-<slug>` and document the scope split in the issue.
- Team Lead, when dispatching parallel work, always declares scope boundaries explicitly: "Dev session A takes files X/Y/Z; Dev session B takes A/B/C. No overlap."

---

## Hand-off pattern: shared branches across agents

Sometimes two agents need to work the same branch sequentially — e.g. PM writes the PRD on `feat/123-foo`, then Dev extends the same branch with the implementation. Git only allows one worktree to have a given branch checked out at a time, so the second agent will hit:

```
fatal: 'feat/123-foo' is already checked out at '.worktrees/pm-123'
```

**Canonical fix — releasing agent prunes its worktree on hand-off.** When you finish your part of the work on a shared branch, push your commits and then:

```bash
# from the primary repo path
git worktree remove .worktrees/<your-task-id>
```

The next agent can then `git worktree add .worktrees/<their-task-id> -b <branch> origin/<branch>` cleanly.

**Fallback when the previous worktree is still open** (e.g. you can't reach the previous session to release it): create a worktree in **detached HEAD** mode and push back to the shared branch by ref:

```bash
git fetch origin
git worktree add --detach .worktrees/<your-task-id> origin/<branch>
cd .worktrees/<your-task-id>
# ... edit, commit ...
git push origin HEAD:<branch>
```

This avoids the branch-checkout conflict (the worktree never claims the branch) while still landing your commits on it. Document in your PR comment that you used the detached-HEAD fallback so the operator knows the previous worktree still needs cleanup.

---

## Auditing what's open

```bash
git worktree list
```

If you see stale worktrees (PRs merged weeks ago), prune them. Long-lived worktrees are a code smell.

---

## When NOT to use a worktree

- **Read-only operations.** If you're only reading code (e.g., answering "where is X defined?"), you don't need a worktree.
- **Repo-wide chores** like updating `CLAUDE.md` or `.claude/agents/*.md` (the operator-self-merge lane in some projects). These are often safe to do in the primary path with the operator's awareness.

Use judgment: the rule is "before you make a branch and commit, you create a worktree." If your work doesn't involve a branch, you don't need a worktree.
