---
description: Dispatch N parallel dev-agent sessions against a partitioned task list (mass refactor, bulk test-writing, codebase audit). Coordinated by git lockfiles. Do NOT use for most coding work — sequential is usually right.
---

# /swarm — N parallel Claudes on partitionable work

## Usage

```
/swarm <oracle> <agent-count>
/swarm 'find . -name "*.rs" -path "*/handlers/*"' 8
/swarm 'pytest --collect-only -q | grep "^test"' 12
/swarm tasks.txt 4              # one unit per line
```

## What this command does

1. **Resolve the oracle** to a list of units (the partition). If the oracle is a shell command, run it; if a file, read it.
2. **Confirm with the operator** before spawning if N > 4 or units > 50 — costs scale with both.
3. **Scaffold the swarm** at `.worktrees/swarm-<utc-ts>/`:
   - `current_tasks/<unit>.lock` for each unit
   - `progress/` directory (initially empty)
   - `agents/agent-0/` … `agents/agent-N/` worktrees (each off origin/main)
   - `AGENT_PROMPT.md` (operator confirms before spawning)
4. **Spawn N parallel `claude -p`** sessions, each running the agent loop:
   - Pick the next unclaimed unit (atomic rename)
   - Run against the unit
   - Push to its own branch
   - Mark `progress/<unit>.done`
   - Loop until no units remain
5. **Watch** — print progress every 30s, file-count claimed/done/failed.
6. **Stop conditions**: all done, N consecutive no-claim iterations, or cost-cap from `evals/results/swarm-<id>/cost.json`.
7. **Aggregate** — produce a single combined PR (or N small PRs, operator's choice) once the swarm finishes.

## Preconditions

- **You have an oracle.** If you don't have a one-sentence partition rule, don't swarm. See `swarm-dispatch` skill.
- **CI is green on main.** Swarms regress old features when partition leaks; CI is the immune system.
- **Cost budget is approved.** Per the C-compiler post: $20K for ~2,000 sessions. Confirm with operator before spawning anything > ~$50.

## Anti-patterns

- **Swarming most coding work.** Per the [multi-agent post](https://www.anthropic.com/engineering/multi-agent-research-system): "most coding is sequential." Burst for partitioned bulk work only.
- **Swarming without an oracle.** Becomes a collision generator.
- **Coordinator agent.** Defeats the C-compiler insight. Git is your coordinator.

## Related

- `swarm-dispatch` skill — the discipline behind this command
- `research-burst` skill — sibling pattern, for breadth-first questions
- `worktree-management` skill — the isolation primitive
- `/eval` — run the eval suite after the swarm to catch regressions
