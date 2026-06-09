---
name: research-burst
description: Use when the work is breadth-first discovery — competitive analysis, library evaluation, codebase audit, design-doc research, "survey of options". Spawns 3-5 parallel research-agent subagents with the lead-worker pattern. Each returns ≤2K token summary. Costs ~15x a chat; reserve for high-leverage questions.
---

# research-burst — lead-worker pattern for breadth-first questions

From the [multi-agent research system post](https://www.anthropic.com/engineering/multi-agent-research-system): a `LeadResearcher` (Opus) decomposes the query, spawns 3-5 parallel subagents (Sonnet), each with its own context window. Outperforms single-agent by ~90% on breadth-first tasks. Costs ~15x a chat ("token usage explains 80% of performance variance").

## When to burst

| Good fit | Bad fit |
|---|---|
| "What libraries solve X? Compare them." | "Fix this bug." |
| "How is feature Y implemented across our codebase?" | "Implement this feature." |
| "What are the design tradeoffs for Z architecture?" | "Optimize this function." |
| "Survey of approaches in published research" | "Refactor this module." |

**Coding is almost always sequential.** Burst for *discovery*, not for *building*.

## Anatomy

```
Operator question → team-lead-agent decides to burst
                       ↓
                research-agent (orchestrator)
                ↓        ↓        ↓        ↓
            sub-1     sub-2    sub-3    sub-4    (parallel, separate context)
                ↓        ↓        ↓        ↓
            findings/sub-1.md  ...
                ↓
        research-agent synthesizes → memory/NOTES.md
                ↓
        citation-agent verifies claims → optional adjustments
                ↓
        Final report posted to operator
```

## Scaling rules (encode in the orchestrator prompt)

| Question shape | Sub-agents | Tool calls each |
|---|---|---|
| Simple fact-find | 1 | 3-10 |
| Comparison of 2-4 options | 2-4 | 10-15 |
| Complex synthesis | 5-10 | 20+ |

## The orchestrator prompt (template)

```
You are research-agent. Your job is to answer the operator's question by
decomposing it, spawning N parallel sub-agents, and synthesizing.

Question: <verbatim>

Step 1 — Decompose.
  Use the think tool. List 3-5 sub-questions that, answered together,
  answer the operator's question. Each must be independently answerable.

Step 2 — Spawn sub-agents.
  For each sub-question, spawn a research-sub-agent via the Agent tool.
  Each sub-agent gets a focused prompt (50-200 words), a token budget
  matched to the question shape, and instructions to write findings to
  findings/sub-<i>.md and return a ≤2,000-token summary.

Step 3 — Wait + read.
  When all return, read findings files (not just the summaries — context
  may have been lost).

Step 4 — Synthesize.
  Produce the answer. Cite each claim by filename + line range.

Step 5 — Hand to citation-agent.
  Pass the synthesized report; it verifies each claim resolves to its
  cited source. Iterate if any claims fail verification.
```

## Sub-agent prompt heuristics

- **Start wide → narrow.** First tool call casts a broad net; later calls drill into the most promising results.
- **Interleaved thinking after each tool result.** Use think tool to assess what the result tells you before the next call.
- **Prefer specialized tools.** The right grep/glob/WebFetch for the question, not the same tool for every question.
- **Match tool to user intent.** Operator wants code? Read source. Operator wants performance numbers? Run benchmarks or fetch docs.

## Filesystem hand-off (avoid game-of-telephone)

Sub-agents write to `findings/sub-<i>.md`, return ≤2K-token summaries. The orchestrator reads files directly when synthesizing — never relies on summaries alone for important details.

## Memory persistence

Long bursts checkpoint the plan to `memory/PROGRESS.md` after every sub-agent return. The 200K window can truncate; the file survives.

## Cost discipline

- Token usage explains 80% of performance variance — but that's variance *within* the right pattern. Don't burst when sequential suffices.
- Upgrading the model beats doubling token budget (per the post).
- Burst budget tracked in `evals/results/research-<id>/cost.json`.

## Anti-patterns

- **Spawning 50 sub-agents** for a question that fits in 1 chat. 15× cost for no gain.
- **Endless searching** for nonexistent sources. Set per-sub-agent tool-call ceilings.
- **Vague sub-task descriptions** → duplicate work + coverage gaps.
- **No CitationAgent pass.** "I found X" claims without source resolve to "I hallucinated X" surprisingly often.
- **Using burst for coding.** Sequential is the right shape for almost all coding work.

## Related

- `/research` command — actually invokes the burst
- `research-agent.md` — the orchestrator's role file
- `citation-agent.md` — verifies claims
- `swarm-dispatch` skill — sibling pattern for partitionable bulk *work* (not discovery)
