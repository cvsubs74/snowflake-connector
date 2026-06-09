---
description: Six forcing questions before writing code — reframe the request and surface the real problem.
---

# Office Hours

Adapted from [garrytan/gstack](https://github.com/garrytan/gstack)'s `/office-hours` — used and credited under MIT license.

Before writing any code for this idea, run the operator through six forcing questions. The goal is to reframe the request: most product asks describe a feature, but the underlying pain is bigger or different. Your job is to surface the real problem, not implement the stated one.

**Posture:**
- Push back on the framing. If the operator described a feature, ask what pain they were trying to relieve.
- Ask one question at a time. Six total questions, max. Don't dump a checklist.
- After each answer, paraphrase what you heard so the operator can correct you.
- At the end, propose 2–3 implementation approaches with effort estimates ("2 weeks human / ~1 hour AI-assisted") and a recommended scope.

## The six questions

Ask these in order. Skip a question only if the answer is already obvious from prior context.

1. **The pain.** "Tell me about the most recent time this was painful. What specifically happened?"
   - Listen for concrete incidents, not abstractions. "Users find it confusing" is not an answer; "yesterday I spent 20 minutes trying to find the export button" is.

2. **Who has the pain.** "Who else has felt this pain? Just you, or a class of users?"
   - If just the operator: smaller scope, ship the wedge, validate before generalizing.
   - If a class of users: deserves a proper PRD.

3. **What they tried.** "What have you (or they) tried already? What didn't work?"
   - Tells you what NOT to build. Often surfaces a Layer 1 (tried-and-true) solution the operator dismissed for reasons worth understanding.

4. **The premise check.** "What's the assumption underneath this request that, if wrong, would change the whole approach?"
   - Often the operator has an unexamined assumption ("we need a dashboard") that, when surfaced, isn't actually needed ("we need to know when X happens — could be an email").

5. **The 10-star version.** "If we boil the lake on this, what does the perfect version look like? Not 'realistic' — perfect."
   - Then: "What's the wedge — the narrowest version that still solves the pain?"
   - These two ends of the spectrum let you propose an implementation that sits between them.

6. **Success metric.** "How will you know it worked? What changes about how you (or they) work?"
   - If you can't articulate this, the feature isn't ready to ship — go back to question 1.

## After the questions

Present:

```
## What I heard

You described <stated request>. What I actually heard is <reframed problem>.

## Implementation alternatives

1. **<Wedge>** — <one-sentence description>. Effort: <X human / Y AI-assisted>. Trade-off: <one line>.
2. **<Medium>** — ... Effort: ... Trade-off: ...
3. **<10-star>** — ... Effort: ... Trade-off: ...

## Recommendation

<one of the above>, because <reason>.

## What I need from you to proceed

- <Decision 1>
- <Open question>
```

If the operator approves the recommendation, hand off:

- If user-facing scope: file a PRD via PM Agent (`Agent(subagent_type: "pm-agent", prompt: "Write PRD for <reframed problem>. Operator approved scope: <wedge|medium|10-star>. Discovery notes: <summary>")`).
- If it's a bug fix or small refactor: file the issue directly and let Dev Agent pick up.

Do NOT write code in this skill. Office Hours is a thinking tool, not an implementation tool.
