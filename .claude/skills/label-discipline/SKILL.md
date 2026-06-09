---
name: label-discipline
description: "Canonical 12-label table for GitHub issues + ownership rules. Every agent references this file for label definitions."
---

# Label Discipline — Canonical Reference

This is a **reference skill** (pure documentation, no allowed-tools). Every role agent references this file for label definitions and ownership rules. The tables here are the single source of truth.

---

## Canonical Label Table

| Label | Description | Owner (applies) | Applied when | Removed when |
|---|---|---|---|---|
| `bug` | Regression or breakage. Fast-path — skips the backlog. | QA Agent / Dev Agent / Triage Agent / Operator | A regression or breakage is confirmed or suspected | Issue is `resolved` (QA closes) |
| `enhancement` | New feature, refactor, cleanup, tooling. | Anyone | Filing any non-bug improvement request | Issue is closed (resolved or rejected) |
| `backlog` | Awaiting PM triage. Removed only by PM. | Filer (incl. Dev, QA, PM) at filing time | Any enhancement is filed (until PM triages) | PM triages: either removes + adds `prioritized` OR closes as rejected |
| `prioritized` | PM has triaged and approved for Dev pickup. | **PM only** | PM approves an enhancement for Dev | Dev completes all work and issue is closed |
| `priority:high` | High priority — blocks operator workflow, security/correctness issue, or required precondition for other prioritized work. | **PM only** | PM assigns high priority at triage | PM changes priority or issue closes |
| `priority:medium` | Medium priority — clear value, no active blocker. Safe default when uncertain. | **PM only** | PM assigns medium priority at triage | PM changes priority or issue closes |
| `priority:low` | Low priority — cleanup, polish, nice-to-have. | **PM only** | PM assigns low priority at triage | PM changes priority or issue closes |
| `in-progress` | Dev Agent has started the fix or feature. | **Dev only** | Dev picks up issue from the queue | PR for the issue merges (or Dev drops the issue) |
| `in-review` | PR is open, awaiting Code Reviewer Agent. | **Dev only** | Dev opens the PR | PR is merged or closed |
| `resolved` | QA Agent verified the fix post-merge (two consecutive passes). | **QA only** | QA completes post-merge verification and passes | Never removed once applied (terminal state) |
| `pm` | Sub-classification: PM Agent filed or owns this issue. | PM Agent | PM files a PRD-driven issue | Optional; never removed; provenance only |
| `qa` | Sub-classification: QA Agent filed or owns post-merge verification. | QA Agent | QA files a bug or enhancement | Never removed once applied; QA owns verification even if issue transfers |

---

## 4 Hard Rules

1. **Bugs SKIP the backlog.** A `bug`-labeled issue is never labeled `backlog`. Bugs go directly from filer to Dev Agent (fast-path). No PM triage required or permitted.

2. **Only PM applies `prioritized` + `priority:*`.** No other agent self-promotes a backlog item. Dev waits for PM to apply `prioritized` + exactly one of `priority:high|medium|low` before picking up any enhancement. A `prioritized` issue always pairs with a `priority:*` label.

3. **Only QA applies `resolved`.** QA Agent applies `resolved` only after two consecutive passing verification runs (the §TWO-PASS rule). No other agent closes an issue as resolved.

4. **Only Dev applies `in-progress` + `in-review`.** These are Dev's status signals. Code Reviewer and PM read them; they do not write them.
   - **`in-review` is hook-enforced** (Hook 2 / `restricted-label-ownership.sh`): any attempt by a non-Dev agent to apply it is mechanically blocked.
   - **`in-progress` is convention-only** — no hook protects it. Dev applies it by discipline on issue pickup. If another agent mistakenly sets it, no workflow gate fails; the label is purely informational.

---

## Operator Override Clause

The operator can override any label rule directly (e.g., apply `prioritized` manually to skip PM triage, assign a `backlog` issue directly to Dev, waive the designer-gate on a frontend PR). When the operator gives an explicit instruction that contradicts the rules above, specialists follow the operator instruction. The override should be noted in the issue comment or PR body for audit trail.

---

## Bootstrap the labels in a fresh repo

The boilerplate doesn't ship label-creation scripts (different teams use different GitHub Actions / setup flows), but here's a one-shot to bootstrap on a fresh repo:

```bash
gh label create bug          --color d73a4a --description "Regression or breakage — fast-path, skips backlog"
gh label create enhancement  --color a2eeef --description "New feature, refactor, cleanup, tooling"
gh label create backlog      --color cccccc --description "Awaiting PM triage"
gh label create prioritized  --color 0e8a16 --description "PM has triaged and approved for Dev pickup"
gh label create priority:high   --color b60205 --description "Blocks workflow or required precondition"
gh label create priority:medium --color fbca04 --description "Clear value, no active blocker (safe default)"
gh label create priority:low    --color c2e0c6 --description "Cleanup, polish, nice-to-have"
gh label create in-progress  --color 1d76db --description "Dev has started"
gh label create in-review    --color 5319e7 --description "PR open, awaiting Code Reviewer"
gh label create resolved     --color 0e8a16 --description "QA verified post-merge (two-pass)"
gh label create pm           --color 6f42c1 --description "PM Agent owns / filed"
gh label create qa           --color e99695 --description "QA Agent owns / filed"
```

---

## Cross-References

- **Triage filing rule**: `.claude/skills/file-bug-issue/SKILL.md` — canonical protocol for filing a new `bug` issue.
- **Dev pickup rule**: `.claude/agents/dev-agent.md` §ISSUE PICKUP CRITERIA.
- **PM triage workflow**: `.claude/agents/pm-agent.md` §WORKFLOW.
- **QA resolved gate**: `.claude/agents/qa-agent.md` §TWO-PASS RULE.
