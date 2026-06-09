---
name: swarm-dispatch
description: Use when the work partitions cleanly across many files or test cases (mass refactor, bulk test-writing, codebase audit, dependency upgrade). Spawns N parallel dev-agent sessions coordinated by git lockfiles in .worktrees/. Proven on a 100K-line C compiler. Do NOT use for most coding (which needs shared context).
---

# swarm-dispatch — parallel Claudes with git-lockfile coordination

From the [building a C compiler post](https://www.anthropic.com/engineering/building-c-compiler): 16 parallel Claude Code sessions, no central orchestrator, coordinated by lockfiles in git. Shipped a 100K-line C compiler that builds Linux 6.9. $20K total cost across ~2,000 sessions / 2 weeks.

## When to swarm

The work partitions cleanly via an **oracle** — a list of independent units of work where collision is unlikely.

| Good fit | Bad fit |
|---|---|
| Mass test addition (`pytest --collect-only` is the oracle — N test files) | Building a new feature (subtasks share context) |
| Codebase audit (`find . -name '*.py'` is the oracle — N files to scan) | Most coding work (per multi-agent post: "most coding is sequential") |
| Dependency upgrade across N call sites | Refactoring a single module |
| Bulk migration (file → file rewrite, formulaic) | Anything where one agent's output is another's input |

If you can write the partition rule in one sentence ("each agent owns one file under `src/handlers/`"), swarm. If you can't, don't.

## Anatomy of a swarm

```
.worktrees/
├── swarm-<task-id>/
│   ├── current_tasks/             # the oracle's output, one file per unit
│   │   ├── api_handlers.lock      # agent claims by overwriting
│   │   ├── auth_handlers.lock
│   │   └── ...
│   ├── progress/
│   │   ├── api_handlers.done      # agent emits on completion
│   │   └── ...
│   └── agents/
│       ├── agent-0/               # worktree per agent
│       ├── agent-1/
│       └── ...
```

Each agent's loop:

```bash
while true; do
  unit=$(ls current_tasks/ | head -1)    # pick a unit
  [ -z "$unit" ] && break                # swarm done
  unit_id="${unit%.lock}"

  # Claim by atomic rename — if another agent already grabbed it, retry.
  if mv "current_tasks/$unit" "current_tasks/$unit.claimed-by-$AGENT_ID" 2>/dev/null; then
    cd ".worktrees/swarm-<id>/agents/$AGENT_ID"
    claude -p "$(cat AGENT_PROMPT.md | sed s/UNIT/$unit_id/g)"
    git push origin "$AGENT_ID/$unit_id"
    echo "done" > "../../progress/$unit_id.done"
  fi
done
```

## The oracle is the unlock

The C-compiler swarm initially failed because tasks were monolithic — every agent fix-and-overwrote the same bug. The team added a **GCC oracle** that partitioned Linux files across agents. After that, agents stopped colliding.

If you don't have an oracle, your swarm becomes a collision generator. Spend the upfront time to define the partition.

## The agent prompt

```markdown
# AGENT PROMPT (UNIT={{UNIT_ID}})

You are one of N parallel Claude Code sessions working on this task. Your unit is **{{UNIT_ID}}**. Other agents are working on other units.

## Rules
- You own ONLY files matching the unit pattern: <pattern>
- Do NOT edit files outside your unit, even if you see a bug
- If you discover a cross-cutting issue, write it to `../../findings/<your-id>.md` (don't fix it)
- Commit + push when your unit passes its acceptance test
- Run `<acceptance-cmd>` after every change; the loop exits only when it's green

## Acceptance
<the specific test or check that says this unit is done>

## What "done" looks like
- All tests in <test-target> pass
- No edits outside <pattern>
- Commit message: "swarm: <unit-id> — <one-line summary>"
```

## Stopping conditions

- All `current_tasks/*.lock` claimed and corresponding `progress/*.done` written
- N consecutive iterations with no new claims (swarm wedged — investigate)
- Total cost budget exceeded (`evals/results/swarm-<id>/cost.json`)

## Model-friendly test harness

Per the C-compiler post:

- **Structured output**: "ERROR + reason on same line" so agents can `grep`.
- **`--fast` flag** that runs 1–10% random sample to avoid context pollution.
- **Pre-computed aggregate stats** so the model doesn't recompute.

A swarm that wastes 2× tokens because the test harness is chatty is a swarm that costs 2×.

## Anti-patterns

- **Spawning N for trivial work.** The 15× token multiplier (per multi-agent research post) is not justified.
- **No oracle / no partition rule.** Becomes a collision generator.
- **Monolithic task per agent.** Defeats the purpose; you get N redundant attempts.
- **Coordinator agent.** Defeats the C-compiler insight. Git is your coordinator.
- **Skipping CI enforcement.** New features regress old ones; CI is the immune system.

## Related

- `/swarm` command — actually invokes the dispatch
- `research-burst` skill — sibling pattern, for breadth-first discovery (not bulk work)
- `worktree-management` skill — the underlying isolation primitive
