# Team Lead Playbook

Project-specific notes that future-you (the Team Lead on this project) needs. Append a section when you learn something worth keeping; delete sections that go stale. Keep this readable end-to-end.

> **When to write here:** after any session where you discovered a coordination gap, a brief that produced wrong behavior, or a cross-agent pattern that cost you a round-trip. One entry per observation — title + what happened + lesson applied next time.
>
> **When NOT to write here:** if the same procedure surfaces in two or more agent playbooks, promote it to `.claude/skills/<name>/SKILL.md` instead. Playbooks are per-agent scratch pads, not team-wide procedures. See the `skill-maintenance` skill for the authoring pattern.

## 2026-05-21 — Background-dispatched specialists need the full operator goal in the brief

**What happened.** Specialist agents (Dev, CR, PM) are spawned as fresh context windows with no memory of the operator's conversation. A brief that says only "pickup #60 and open a PR" is technically complete but operationally thin — the agent has no idea *why* the task matters, what invariants to protect, or how it fits into a larger parallel run.

**What I learned.** Every brief must include, at the top:

- The operator's stated goal (e.g., "parallelism test — 3 disjoint sessions running concurrently").
- Explicit scope boundaries — what files are in-scope vs. which are owned by the other sessions.
- Done criteria stated as measurable outputs (PR URL, test count, line count).

Without this, agents default to generic SDLC behavior and may overlap with sibling sessions or miss context that changes their approach.

**Apply next time.** Structure every brief in three sections: (1) operator goal + parallelism context, (2) your scope + neighboring scopes, (3) done criteria as a table. Use the `dispatch` comment on the tracking issue as the canonical brief — that way any agent can re-read it if spawned late.

## 2026-05-21 — CR sometimes posts LGTM without executing the merge

**What happened.** Code Reviewer sessions on PR #56 (and as a standing risk on other PRs) posted "LGTM" as a comment but did not issue `gh pr merge`. The verdict was orphaned — Dev's `in-review` label stayed on, the issue stayed open, and the PR sat in a merged-but-not-closed state until a follow-up session noticed.

**What I learned.** CR agents treat "post verdict" and "merge" as two separate decisions, and without an explicit instruction to complete both in the same session, the merge step is skipped. The pattern repeats because agents do not re-read prior playbook entries at the start of each session.

**Apply next time.** Every CR brief must contain an explicit close-the-loop instruction: "Complete the full routine IN THE SAME SESSION: (1) post verdict comment, (2) run `gh pr merge <N> --squash --delete-branch`, (3) verify with `gh pr view <N> --json state,mergedAt`." If CR posts LGTM without merging, Team Lead must follow up with a targeted message — do not wait for QA to surface the gap.

## 2026-05-21 — Dev post-merge cleanup is a recurring gap

**What happened.** After PRs #56, #58, and the parallel session for #59–#61, Dev worktrees and local branches accumulated without cleanup. The `in-progress` and `in-review` labels sometimes persisted after merge. Team Status checks (`bin/team-status.sh`) flagged stale worktrees and label drift across multiple sessions.

**What I learned.** Dev agents know the cleanup steps (worktree remove, branch delete, label strip) but consistently skip them when their session ends immediately after the merge confirmation. The issue is sequencing: agents treat "PR merged" as the terminal event and shut down before cleanup.

**Apply next time.** Two mitigations worth pursuing:

1. **Brief-level:** add a mandatory cleanup checklist to every Dev brief: `git worktree remove`, `git branch -D`, confirm labels are clear. Frame it as part of Done Criteria, not a post-note.
2. **Hook-level:** file an enhancement (`[ENH] Hook 7 — auto-strip in-progress/in-review labels on PR close`) so the hook handles label cleanup automatically, removing human-memory dependency. This recurs often enough to justify the hook — file the issue rather than keep writing it in briefs.
