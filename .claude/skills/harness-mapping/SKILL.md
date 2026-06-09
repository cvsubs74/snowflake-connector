---
name: harness-mapping
description: Use when explaining how the 8-agent team maps onto the Planner / Generator / Evaluator harness pattern from the Anthropic harness-design post. Reference when reasoning about who owns what handoff artifact (PRD, design doc, contract, code, verdict).
---

# harness-mapping — 8-agent team onto Planner/Generator/Evaluator

The [harness-design post](https://www.anthropic.com/engineering/harness-design-long-running-apps) shows reliable multi-hour builds come from a three-role topology with file-based handoffs:

- **Planner** — expands a 1-4 sentence prompt into a spec with feature breakdown
- **Generator** — implements
- **Evaluator** — grades against the spec (separate context, GAN-style)

Our 8-agent topology maps onto this cleanly:

| Harness role | Our specialist(s) | Handoff artifact (file) |
|---|---|---|
| **Planner** | pm-agent + designer-agent | `docs/prd/PRD-<topic>.md` + `docs/design/DESIGN-<topic>.md` |
| **Generator** | dev-agent | code on the working branch + `docs/contracts/<N>-<slug>.md` |
| **Evaluator** | qa-agent + code-reviewer-agent | PR review verdict + `resolved` label + eval suite results |
| (orthogonal) | triage-agent | upstream of Planner — turns operator reports into well-formed bug issues |
| (orthogonal) | devops-agent | downstream of Evaluator — deploys after the verdict lands |
| (router) | team-lead-agent | decides which pattern (chain / route / parallel / orchestrate / swarm) per task |

## What this mapping buys us

1. **A named handoff artifact between every pair of roles.** PRD → DESIGN → CONTRACT → CODE → VERDICT. No invisible handoffs.

2. **Context reset, not handoff-by-conversation.** Each role reads the artifacts from the previous role's files (just-in-time retrieval per [context engineering post](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)). Nobody depends on the previous session's chat history.

3. **A clear failure-mode owner.** If the PRD is vague, the Planner failed. If the code doesn't match the contract, the Generator failed. If a regression slips through, the Evaluator failed. The eval suite (`evals/`) measures each independently.

4. **Drop-in swarm mode for partitionable work.** When the work decomposes into N independent file partitions (per the [C compiler post](https://www.anthropic.com/engineering/building-c-compiler)), Generator becomes N parallel dev-agents coordinated by git lockfiles in `.worktrees/*/current_task.lock`. See `swarm-dispatch` skill.

5. **Drop-in lead-worker mode for breadth-first research.** When the Planner needs to explore an open question (competitive analysis, library survey, codebase audit), pm-agent (or designer-agent) becomes the orchestrator and spawns 3–5 parallel research-agents per the [multi-agent research post](https://www.anthropic.com/engineering/multi-agent-research-system). See `research-burst` skill.

## When the mapping does NOT apply

- **Trivial work** (typo, one-line bug). No need for the full three-role choreography; dev-agent owns it end-to-end and skips the contract.
- **Operator-driven exploration** ("show me how X works in our codebase"). team-lead-agent answers directly or delegates to a single specialist; no Planner/Generator/Evaluator triad needed.
- **Hotfix incidents.** triage-agent and dev-agent collapse Planner/Generator into one role under time pressure; Evaluator catches up post-merge.

## What this mapping is NOT

- It is **not a new agent topology.** The 8 specialists are unchanged. This skill just names which harness role each specialist plays so that the contract and eval flows are unambiguous.
- It is **not a process change for trivial work.** The contract is optional for one-line fixes; the Planner role is no-op when the operator brings a PRD-ready ask.

## Related

- `contract-negotiation` — the Generator ↔ Evaluator handoff artifact
- `swarm-dispatch` — burst-mode Generator for partitionable work
- `research-burst` — burst-mode Planner for breadth-first questions
- `eval-runner` — measures each role's output quality independently
- `system-role-boundaries` — the canonical 8-agent contract (this skill complements; does not replace)
