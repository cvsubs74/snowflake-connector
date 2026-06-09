# memory/ — durable agent state

This directory holds state that **survives context compaction and session resets**. It is the agent's external brain — the thing it reads on cold start to know what's going on.

Three files, three purposes:

| File | What goes in it | Who writes |
|---|---|---|
| `PROGRESS.md` | Active goals, in-flight tasks, "what we're doing right now" | Whichever agent is currently driving |
| `DECISIONS.md` | Architectural choices + why (mini-ADRs). Append-only. | The agent that made or ratified the decision |
| `NOTES.md` | Structured note-taking output — observations, leads, things-to-check-later | Any agent during exploration |

## Reading discipline

- **Cold-start checklist:** every specialist session begins by reading these three files before touching code. The `session-opener.sh` hook reminds you.
- **Subagents return summaries, not raw exploration** — but they may write durable findings here.
- **Never duplicate** — if it's in `DECISIONS.md`, don't restate it in `PROGRESS.md`.

## Writing discipline

- **PROGRESS.md** — keep it short. Active state only. When a goal is done, remove it (don't archive). Old goals live in `git log`.
- **DECISIONS.md** — append-only. Each entry: date, decision, why, alternatives considered, who/what triggered it. Never edit a past decision; supersede it with a new entry that links back.
- **NOTES.md** — bullet-and-prune. Read before code; prune anything stale before close.

## Why three files instead of one

Inspired by Anthropic's [context-engineering guidance](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents): structured external memory beats one giant scratchpad. Different access patterns (active vs. historical vs. exploratory) → different files.
