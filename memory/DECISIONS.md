# Architectural decisions

> Append-only log. Each entry: date · decision · why · alternatives · trigger. Supersede, don't edit.

---

## 2026-05-25 · Evolve `claude-workflow` in place rather than fork a new template

**Decision.** Add evals, memory, contracts, sandboxing, MCP, burst modes, and postmortem-prevention hooks as additive PRs to this repo. Do not create a separate "v2" template.

**Why.** The existing 8-agent topology + worktree discipline + PRD→Design→code gate is the substrate the Anthropic engineering corpus validates. Burning it would be expensive churn.

**Alternatives considered.**
- *Fork `claude-workflow-lite`*: a single-Claude minimalist alternative. Worth considering as a downstream offshoot, not the primary target.
- *Greenfield repo*: would lose the accumulated playbook knowledge and skill-maintenance discipline.

**Trigger.** Research synthesis across all 24 Anthropic engineering posts; no pattern requires throwing out the substrate.

---

## 2026-05-25 · Map the 8-agent team onto the Planner / Generator / Evaluator harness pattern

**Decision.** PM-agent + Designer-agent = Planner. Dev-agent = Generator. QA-agent + Code-Reviewer-agent = Evaluator. Triage and DevOps remain orthogonal. Team Lead = router/budget allocator (orchestrator, not manager).

**Why.** The [harness-design post](https://www.anthropic.com/engineering/harness-design-long-running-apps) shows reliable multi-hour builds come from a three-role topology with file-based handoffs and a `contract.md`. Our specialist roles already fit; the mapping just makes the contract explicit.

**Alternatives considered.** Add new Planner/Generator/Evaluator agents alongside the existing 8. Rejected — duplication, not clarity.

**Trigger.** Five parallel research agents converged on the P/G/E shape as the canonical multi-hour build pattern.

---

## 2026-05-25 · `memory/` is the durable substrate; `CLAUDE.md` stays bedrock-only

**Decision.** Active state, decisions, and exploration notes go in `memory/{PROGRESS,DECISIONS,NOTES}.md`. `CLAUDE.md` stays ≤200 lines and contains only what every session needs to know (ethos, agent topology, command cheatsheet).

**Why.** "Would removing this cause mistakes?" prune test from the [Claude Code best practices post](https://www.anthropic.com/engineering/claude-code-best-practices). Anything that's *current state* (vs. *bedrock*) belongs in memory/.

**Trigger.** Context-engineering research: file-based state outperforms in-context state for long-running work.
