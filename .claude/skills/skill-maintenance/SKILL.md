---
name: skill-maintenance
description: "How to update an agent's own role file or a shared skill — the agent-doc-PR pattern, the line-cap discipline, when to edit your own contract."
---

# Skill Maintenance — Editing Agent Files and Shared Skills

The agent files (`.claude/agents/<role>-agent.md`) and shared skills (`.claude/skills/<name>/SKILL.md`) ARE the operating contract. When you discover a pattern that works (or an anti-pattern that bites you), the right response is often to edit the contract so the next session benefits.

This skill is the protocol for doing that safely.

---

## When to edit

### Edit when:

- You discovered a coordination pattern that works and isn't documented yet. (Add it to the relevant agent file or shared skill.)
- You hit an anti-pattern that wasn't called out. (Add it to the agent's anti-patterns section.)
- You found a label / workflow edge case the contract didn't cover. (Add the edge case + the resolution.)
- A skill file is now stale (references removed services, obsolete commands, outdated env vars).

### Do NOT edit when:

- You disagree with an existing rule but can't articulate the failure mode it prevents. (Surface to operator first.)
- You're proposing a structural change to the team topology (adding / removing an agent, redrawing label ownership). (Operator decision.)
- The edit is opinion or style without an underlying incident. (Skills should be load-bearing, not aspirational.)

---

## How to edit (the PR pattern)

Skill / agent file edits go through a normal PR, just like code:

1. **Worktree.** Create a worktree per `.claude/skills/worktree-management/SKILL.md`.

2. **Branch.** `docs/skill-<short-slug>` or `docs/agent-<short-slug>`.

3. **Edit.** Make the change. Keep it surgical — don't rewrite the file just because you're touching one section.

4. **Update cross-references.** If you renamed a section heading, search the rest of `.claude/` for references and update them.

5. **PR.** Title: `docs(skills): <what changed>`. Body explains the failure mode that prompted the edit + a one-line example of the new behavior.

6. **Review.** In most projects, agent-doc PRs follow the same review path as code (Code Reviewer reviews + merges). Some projects allow operator self-merge for trivial doc-only changes — follow your project's convention.

---

## Line-cap discipline

Agent files and shared skills should be **readable end-to-end in one sitting**. Soft cap: ~400 lines. Hard cap: ~700.

If you're about to push an agent file over 700 lines:

- **Extract a shared skill.** Move the largest single section to `.claude/skills/<name>/SKILL.md` and reference it from the agent file.
- **Look for duplication across agents.** If three agents have similar "how to file an issue" sections, that's a shared skill.
- **Delete examples that no longer represent the current state.** "Here's how we used to do X" is not a contract; it's archaeology.

---

## Cross-reference, don't duplicate

When two agents need the same rule (e.g., the label table), one of them carries the canonical version (or it lives as its own skill under `.claude/skills/<name>/`) and the others reference it:

```markdown
## Label authority

- Apply: `bug`, `qa`, `enhancement,backlog`
- See `.claude/skills/label-discipline/SKILL.md` for full label table.
```

Never inline the same table in two files. When it changes, you'll update one and forget the other.

---

## What goes in an agent file vs a shared skill

| Goes in agent file | Goes in shared skill |
|---|---|
| The agent's identity and role | Cross-agent contracts (labels, topology) |
| The agent's exclusive labels | Reusable protocols (filing bugs, creating worktrees) |
| The agent's workflow | Canonical reference tables |
| The agent's cold-start anchor | Anything referenced by 2+ agents |
| Agent-specific anti-patterns | Patterns multiple agents share |

When in doubt: if you'd reference it from a second agent's file, it belongs as its own skill under `.claude/skills/`.

---

## Anti-patterns

- **Editing a contract to match a one-off incident.** Wait until the pattern recurs before codifying.
- **Adding rules without a failure mode.** Every rule should have "this prevents X" in its motivation.
- **Letting line count creep.** A 1200-line agent file is unread.
- **Inlining tables that already exist as a shared skill.** Always reference.
- **Renaming sections without updating cross-references.** Use `grep -r "§SECTION-NAME" .claude/` before merging.
