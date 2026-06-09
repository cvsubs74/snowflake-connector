# SDLC — Software Development Lifecycle

How work flows through this repo: from idea to merged PR to deployed change. This is the team's workflow contract. Specialists (Dev / QA / Code Reviewer / DevOps / etc.) enforce it; operators can override with explicit instruction.

---

## Step 0 — Does this need a PRD + Design Doc?

| Type | PRD required? | Design Doc required? |
|---|---|---|
| New user-facing feature | ✅ Yes | ✅ Yes |
| Refactor with user-visible behavior change | ✅ Yes | ✅ Yes |
| Refactor with no behavior change | ❌ | Optional |
| Bug fix | ❌ | ❌ |
| Chore / tooling / dep upgrade | ❌ | ❌ |
| Hotfix | ❌ | ❌ |

- **PRDs** live in `docs/prd/PRD-<topic>.md` and are owned by PM.
- **Design Docs** live in `docs/design/DESIGN-<topic>.md` and are owned by Dev (or Designer for UX-heavy work).
- PRDs precede design docs precede code. Skipping the gate without explicit operator override blocks the PR at review.

---

## Step 1 — Pick up an issue

Dev picks up an issue if and only if **one** of:

1. The issue has the `bug` label (with or without `qa`). Bugs bypass the backlog.
2. The issue has the `prioritized` label (PM has triaged). Highest priority first (`priority:high` > `medium` > `low`).
3. The operator has explicitly assigned/asked Dev to work on it.

Never pick up an issue still labeled `backlog` — that's PM's queue.

---

## Step 2 — Branch + worktree

Each specialist session creates its own worktree off the default branch:

```bash
git fetch origin
git worktree add .worktrees/<task-id> -b <branch-name> origin/main
cd .worktrees/<task-id>
```

**Branch naming:**

```
<type>/<issue-number>-<slug>
```

Examples:
- `fix/123-validation-overflow`
- `feat/456-bulk-import`
- `chore/789-upgrade-typescript`
- `refactor/234-extract-auth-helper`

Types: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`, `perf`.

Never edit in the primary repo path. Never reuse another session's worktree.

---

## Step 3 — Build + verify locally

- Run the relevant test suite for what you touched. Don't rely on CI to catch what you could have caught locally in 30 seconds.
- For UI changes, start the dev server and exercise the actual flow in a browser. Type-check passing ≠ feature working.
- Run lint / format before committing.

---

## Step 4 — Commit + push

**Commit message format:**

```
<type>(<scope>): <short summary>

<optional body — what changed and why; reference issues>

Refs #<issue>   (or)   Closes #<issue>
```

**`Refs` vs `Closes` discipline:**

- Use `Closes #N` only when this PR fully resolves the issue. Closes auto-closes the issue on merge.
- Use `Refs #N` when this PR is part of a multi-PR effort. The umbrella issue stays open until the FINAL PR uses `Closes`.

Never use `Closes` on a slice that doesn't finish the issue — it strands the rest of the work.

---

## Step 5 — Open PR

**PR title** mirrors the commit summary.

**PR body must include `Closes #<issue>` so GitHub auto-closes the tracking issue on merge.** Use `Refs #<issue>` only when this PR is a partial slice and the issue should stay open.

**PR body template:**

```markdown
## Summary
<1-3 bullets — what changed and why>

## Test plan
- [ ] <how the reviewer can verify this works>
- [ ] <edge case 1>
- [ ] <edge case 2>

## Notes / risks
<anything reviewer should pay extra attention to; flag any
cross-flow contract touch points>

Closes #N  (or Refs #N if this is part of a multi-PR effort)
```

Apply `in-review` label (Dev's signal; Code Reviewer watches for it). PRs must pass CI (shellcheck, bash syntax, markdown lint) before Code Reviewer merges.

**Designer gate (convention-only):** For PRs touching frontend paths (UI components, styles, layout), Code Reviewer waits for Designer to post a top-level "Design Approved" comment before squash-merging. No hook enforces this — Code Reviewer is on the honor system. If Designer posts "Design Blocked," Code Reviewer posts `CHANGES REQUESTED` and Dev iterates. (Hook 7 to enforce this mechanically is the documented upgrade path if this repo gains a meaningful UI surface.)

---

## Step 6 — Review

Code Reviewer:

1. Reads the diff in PR order, not file order (commits often tell a story).
2. Checks the test plan was actually executed.
3. Calls out cross-flow contract violations (if your repo has shared contracts, e.g. schema / API surface / IPC protocol).
4. Posts one of three verdicts as a comment prefix:

```
LGTM — <one-line summary> → merge
CHANGES REQUESTED — <what to change> → Dev iterates
DISCUSS — <open question> → conversation
```

5. On LGTM, squash-merges using `bin/merge-pr.sh` (REQUIRED — never call `gh pr merge` directly from agent context):

   ```bash
   bin/merge-pr.sh <N> --squash
   ```

   `bin/merge-pr.sh` calls `gh pr merge <N> --squash --delete-branch` and then immediately runs worktree cleanup. This is required because `PostToolUse` hooks from `settings.json` do not fire in agent sub-sessions (anthropics/claude-code #34692) — Hook 7 is silent for agent-driven merges. `bin/merge-pr.sh` runs cleanup explicitly, making it work in all contexts.

   `--delete-branch` is still mandatory and enforced by Hook 6 (`pr-merge-requires-delete-branch.sh`) — `bin/merge-pr.sh` always passes it. The repo setting `delete_branch_on_merge=true` is the server-side safety net.

6. The merge comment is the FINAL CLOSER: it summarizes what shipped and pings the next owner (DevOps for deploy, QA for verification).

---

## Step 7 — Deploy (if applicable)

DevOps:

- Watches `main` for merges that touch deployable surfaces.
- Deploys per the project's deploy script / pipeline.
- Posts deploy confirmation on the originating PR.
- On health-check failure, rolls back and pings Dev + operator.

---

## Step 8 — Post-merge verification

QA:

- For bugs: runs the regression scenario; confirms two consecutive passes; applies `resolved`; closes the issue.
- For features: runs the relevant archetype scenarios; files new bugs if regressions surface.

`resolved` is QA's exclusive label. No one else applies it.

---

## GitHub Label Scheme

Canonical reference: `.claude/skills/label-discipline/SKILL.md`.

**Recovery:** if an agent reports a missing label (e.g. `label "prioritized" not found`), run `bin/bootstrap-labels.sh [OWNER/REPO]` to (re-)create the canonical set. The script is idempotent — safe to re-run any time.

| Label | Owner | Meaning |
|---|---|---|
| `bug` | QA / Triage / Dev / Operator | Regression. Skips backlog. |
| `enhancement` | Anyone | New feature, refactor, cleanup, tooling. Always starts with `backlog`. |
| `backlog` | Filer or PM | Awaiting PM triage. Removed only by PM. |
| `prioritized` | **PM only** | PM approved for Dev pickup. Pairs with `priority:*`. |
| `priority:high` | **PM only** | Blocks workflow or required precondition. |
| `priority:medium` | **PM only** | Clear value, no blocker. Safe default. |
| `priority:low` | **PM only** | Cleanup, polish. |
| `in-progress` | **Dev only** | Dev started work. |
| `in-review` | **Dev only** | PR open, awaiting CR. |
| `resolved` | **QA only** | QA verified post-merge. Terminal state. |
| `qa` | QA | QA filed/owns verification. |
| `pm` | PM | PM filed. |

**Hard rules:**

1. Bugs SKIP the backlog.
2. Only PM applies `prioritized` + `priority:*`.
3. Only QA applies `resolved`.
4. Only Dev applies `in-progress` + `in-review`.
5. Team Lead owns no labels.

Operator override: any operator can apply any label directly; agents respect operator-set state.

---

## What never changes

- **GitHub is the single source of truth.** Plans live in operator messages (ephemeral); status lives on issues, PRs, labels (durable). Never create parallel tracking surfaces.
- **No direct commits to `main`** (or whatever your default branch is). Every change goes through a PR + review.
- **Squash-merge on green** — keeps history linear and bisect-friendly.
- **Update `docs/ARCHITECTURE.md`** whenever a change touches module shape, data flow, schema, or major constraints.
