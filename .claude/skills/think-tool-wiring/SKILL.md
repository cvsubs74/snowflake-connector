---
name: think-tool-wiring
description: Use when adding a new policy-heavy specialist agent, when reviewing why an existing agent is making sloppy mid-flight decisions, or when the model is acting on tool output without verifying it against rules. Encodes the "think" tool pattern from Anthropic's research — measured 54% gain on τ-Bench airline.
---

# think-tool-wiring — pause-to-reason mid-trajectory

The [think tool post](https://www.anthropic.com/engineering/claude-think-tool) shows: a no-op `think` capability that lets Claude pause mid-trajectory to reason about tool output produces measurable gains on policy-heavy sequential work (54% relative gain on τ-Bench airline with think + optimized prompt).

In Claude Code we don't ship a separate `think` tool — the harness's built-in thinking capability covers it. What this skill encodes is **when and how to prompt agents to pause and think** after receiving tool results, before acting.

## When the think tool helps

| Yes | No |
|---|---|
| Policy-heavy work (rules + edge cases must be verified before action) | Pure parallel coding |
| Sequential tool use where each output narrows the next decision | Single-shot tool call |
| Triage / classification (must check taxonomy before labeling) | Simple instruction following |
| Code review (verify diff against ethos, style, contract) | Routine file reads |
| QA verification (compare result against acceptance criteria) | Routine refactor |

Our agents that benefit: **dev-agent, code-reviewer-agent, qa-agent, triage-agent**. Our agents that don't: **pm-agent, designer-agent, devops-agent** (more parallel/creative; pausing adds no signal).

## How to wire it into an agent

Add this block to the agent's `.md` file — typically right before the WORKFLOW section:

```markdown
## USING THE THINK TOOL

Before acting on a tool result that you'll use to make a decision, pause and write
out your reasoning explicitly. Use the following pattern:

1. **List the rules that apply** to this situation (from CLAUDE.md, the agent's
   own role file, or the relevant skill).
2. **Check the tool result** against each rule. Where does it fit? Where doesn't it?
3. **State your next action** in one sentence, and **why** it's correct given the rules.

If steps 1–3 reveal a contradiction, **do not act** — surface it to the operator.

### <Example 1: agent-specific worked example>
### <Example 2: agent-specific worked example>
```

The two worked examples are non-negotiable — without them the agent uses think as
a stalling tactic, not a verification step. Calibrate the examples to the agent's
actual policy domain (label rules for Triage, contract verification for QA, etc.).

## Worked-example shape

Each example follows the same structure:

```
<think_tool_example>
Tool result: <verbatim tool output, abridged if huge>

Applicable rules:
- <rule from the agent's role file or CLAUDE.md>
- <another rule>

Check against result:
- <rule 1>: <fit / doesn't fit / partially>
- <rule 2>: <...>

Next action: <one sentence, citing which rule justifies it>
</think_tool_example>
```

## Why this works

From the post:

> Extended thinking runs *before* the response; the think tool runs *during*, after new information arrives.

After-tool-result thinking is the moment when the agent is most likely to skip a
rule check and act on incomplete information. The examples + the explicit pause
collapse that failure mode.

## Anti-patterns

- **Adding the block without examples.** The model treats `think` as optional. Examples make it a contract.
- **Using `think` for parallel coding.** No measurable gain; pure overhead.
- **Generic examples that don't reference the agent's policy.** The model has to imagine the rules; it imagines wrong. Concrete examples from the agent's actual domain.
- **Wiring `think` into low-stakes specialists (PM, Designer).** Their work is breadth/creative; pausing for rule-check provides no signal.

## Related

- `office-hours` — pre-work forcing questions; complementary to `think` (one runs before, one during)
- `investigate` — debugging discipline; uses `think` heavily by design
- `contract-negotiation` — the artifact `think` checks PRs against
