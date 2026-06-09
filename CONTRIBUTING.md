# Contributing to claude-workflow

This is the `claude-workflow` agent-team template — a multi-agent engineering
system built on Claude Code. PRs welcome.

---

## How work flows

Every change originates as a GitHub issue and moves through PM triage, Dev
implementation, Code Reviewer merge, and QA post-merge verification before it
is considered resolved. GitHub is the single source of truth: issues, labels,
and PR state are authoritative; no parallel tracking surfaces. See
[SDLC.md](SDLC.md) for the full workflow contract.

---

## The agent team

Seven specialists — PM, Triage, Dev, QA, Code Reviewer, DevOps, Designer —
are coordinated by a Team Lead. Each specialist owns a specific slice of the
lifecycle; no agent crosses into another's domain unilaterally. Role contracts
and topology live in [.claude/agents/README.md](.claude/agents/README.md).

---

## How to file an issue

- **Bug** (`bug` label): skips the backlog and goes straight to Dev. Use the
  title format `[BUG] <imperative description>`.
- **Enhancement** (`enhancement,backlog` labels): enters PM's triage queue.
  PM decides priority; Dev picks up only after `prioritized` is applied.

Filing protocol and duplicate-check steps:
[.claude/skills/file-bug-issue/SKILL.md](.claude/skills/file-bug-issue/SKILL.md)

Label definitions and ownership rules:
[.claude/skills/label-discipline/SKILL.md](.claude/skills/label-discipline/SKILL.md)

---

## How to open a PR

Branch naming follows `<type>/<issue-number>-<slug>` (e.g.
`fix/123-null-pointer`, `feat/456-bulk-import`). Valid types: `feat`, `fix`,
`chore`, `refactor`, `docs`, `test`, `perf`.

Commit messages use the format:

```
<type>(<scope>): <short summary>

Refs #N    ← partial slice; issue stays open
Closes #N  ← final slice; issue auto-closes on merge
```

Use `Closes #N` only when this PR fully resolves the tracking issue.
See [SDLC.md](SDLC.md) Steps 2–5 for the full branch, commit, and PR
body conventions.

---

## Local development

```bash
# Run the full test suite (shellcheck, hook tests, markdown lint)
bash tests/run.sh

# Snapshot the issue queue and worktree state
bin/team-status.sh

# Bootstrap a fresh clone (labels, hooks, project skeleton)
bin/init-project.sh
```

---

## Code style and principles

Three principles govern every decision the team makes:

- **Boil the Lake** — do the complete thing; completeness is cheap with AI assistance.
- **Search Before Building** — check what exists before designing from scratch.
- **User Sovereignty** — AI recommends, the user decides.

Full details: [ETHOS.md](ETHOS.md)

Coding discipline (think before coding, simplicity first, surgical changes):
[CLAUDE.md](CLAUDE.md) — "Coding discipline" section.

---

## Running the agent team

Type `/onboard-team` in Claude Code to spawn all eight agents with the Team
Lead in the driver's seat. The slash command injects the spawn prompt
automatically from [.claude/commands/](.claude/commands/).

Team topology and "Spawning the team" instructions:
[.claude/agents/README.md](.claude/agents/README.md)
