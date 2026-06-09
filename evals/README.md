# evals/ — agent and product quality measurement

This directory is where we **measure whether our agents and our product are getting better or worse**. It is the single biggest defense against the failure modes called out in the [April 23 postmortem](https://www.anthropic.com/engineering/april-23-postmortem) and the [Sept 2025 postmortem](https://www.anthropic.com/engineering/a-postmortem-of-three-recent-issues).

## What goes here

| Subdir | Purpose |
|---|---|
| `tasks/` | YAML task definitions, one per eval. Tagged `OOD: true` if out-of-distribution. |
| `graders/` | Code-based, LLM-based, and state-based graders. |
| `rubrics/` | Markdown rubrics for LLM and human graders. 0-N points per dimension + passing threshold. |
| `harness/` | `eval_runner.py` and friends — clean env per trial, pass@k + pass^k, multi-time-of-day. |
| `results/` | Per-run transcripts + metrics. **Transcripts are non-negotiable — read them.** |
| `prod_monitor/` | Continuous prod quality (not just canary), cross-platform equivalence, cohort segmentation. |

## Three grader types, three things measured

From [Demystifying evals for AI agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents):

| Grader | Use when |
|---|---|
| Code-based | Outcome verifiable (test passes, file exists, DB row written) |
| LLM-based | Quality judgment needed (is this PRD specific? is this review actionable?) |
| Human | Calibration runs + genuinely subjective domains |

Always measure all three of: **transcript** (turns, tool calls, tokens, TTFB), **outcome** (DB/FS/UI state), **behavior** (rubric grade).

## Non-determinism

Report both:
- **`pass@k`** — at least one of k trials passes (capability ceiling)
- **`pass^k`** — all k trials pass (production reliability)

## Infra noise discipline

From [Quantifying infrastructure noise](https://www.anthropic.com/engineering/infrastructure-noise): infra config alone can produce gaps larger than model-to-model gaps. Every task in `tasks/` declares:

```yaml
resources:
  guaranteed: 1x     # baseline allocation
  ceiling: 3x        # kill threshold
```

Treat <3pp leaderboard differences as noise unless the eval is run with binomial CI reporting.

## Eval-awareness defense

From [Eval awareness / BrowseComp](https://www.anthropic.com/engineering/eval-awareness-browsecomp): host datasets encrypted and auth-gated. Embed canary strings to detect contamination. The `harness/anomaly.py` script flags transcripts where the agent pivots from domain searches to meta-reasoning about benchmark structure (queries containing `benchmark|eval|decrypt|canary`).

## Continuous prod monitoring

`prod_monitor/continuous_quality.py` runs against the **live system, not a canary**. The [Sept 2025 postmortem](https://www.anthropic.com/engineering/a-postmortem-of-three-recent-issues) called out the absence of continuous prod quality eval as the reason a routing bug grew from 0.8% to 16% of requests before detection.

Cohort segmentation is mandatory — never trust an aggregate metric.

## How to add a new eval

1. Write a task YAML in `tasks/<domain>/<name>.yaml`.
2. Pick or write the grader(s) in `graders/`.
3. Write the rubric in `rubrics/` if using an LLM grader.
4. Run via `python evals/harness/eval_runner.py tasks/<domain>/<name>.yaml --trials 3`.
5. Inspect `results/transcripts/` — never trust the metric alone.
6. If the task is stable enough to gate deploys, add it to the CI workflow.

The `eval-runner` skill (`.claude/skills/eval-runner/SKILL.md`) walks through this in detail.
