---
description: Spawn research-agent (lead-worker pattern) to answer a breadth-first question with parallel sub-agents. Use for competitive analysis, library survey, codebase audit, design-doc research. Costs ~15x a chat — reserve for high-leverage questions.
---

# /research — breadth-first discovery with parallel sub-agents

## Usage

```
/research <question>
/research "What rate-limiter libraries should we evaluate? Top 5 with trade-offs."
/research "How does our codebase handle pagination across services? Inconsistencies?"
```

## What this command does

1. **Route to research-agent** via the Agent tool (subagent_type: research-agent).
2. **research-agent decomposes** the question into 3–5 independently answerable sub-questions (see `research-burst` skill for scaling rules).
3. **Spawns sub-agents in parallel** — one per sub-question. Each runs in its own context window, writes findings to `memory/research/<task-id>/sub-<i>.md`, returns ≤2K-token summary.
4. **Synthesizes** with citations to the findings files.
5. **Hands to citation-agent** for verification — every cited claim resolves to its source.
6. **Returns the verified report** + updates `memory/NOTES.md` with the headline.

## When to use

- "Compare X, Y, Z and recommend"
- "Survey of approaches to <problem>"
- "How do we currently handle <pattern> across the codebase?"
- "What does the literature say about <design decision>?"

## When NOT to use

- Single-source questions ("what does this file do") → just read the file.
- Coding ("implement this") → use dev-agent.
- Bug fix → use triage-agent + dev-agent.
- Quick answer the model already knows → skip the burst.

## Cost discipline

Per the [multi-agent research post](https://www.anthropic.com/engineering/multi-agent-research-system): bursts cost ~15× a chat. Confirm with operator before bursting if the question feels marginal. Track cost in `memory/research/<task-id>/cost.json`.

## Related

- `research-burst` skill — the discipline behind this command
- `research-agent.md` — the orchestrator's role file
- `citation-agent.md` — verification pass
- `/swarm` — sibling command, for partitionable bulk work (not discovery)
