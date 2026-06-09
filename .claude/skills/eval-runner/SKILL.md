---
name: eval-runner
description: Use when adding a new eval task, running the eval suite over recent changes, or interpreting eval results. Encodes the three-grader pattern (code/LLM/human), pass@k vs pass^k, infra-noise discipline, and the eval-awareness defense.
---

# eval-runner — add and run agent/product evals

Evals are how we know whether changes made things better or worse. This skill walks through (a) adding a new eval task, (b) running the suite, (c) reading the results.

If you're tempted to ship a change without an eval gating it: stop. Either write the eval first, or accept that you have no quality signal and the change is a guess.

## Checklist for adding a new eval

1. **Pick the grader type.**
   - **Code-based** — outcome is verifiable by file I/O / shell / static analysis. Use `evals/graders/code_grader.py`.
   - **LLM-based** — quality judgment needed (is this PRD specific? is this review actionable?). Use `evals/graders/llm_grader.py` + a rubric in `evals/rubrics/`.
   - **State-based** — outcome is "the world ended up in state X". Use `evals/graders/state_grader.py`.
   - You can combine multiple graders per task; `scoring_rule: binary_and` requires all to pass.

2. **Write the task YAML at `evals/tasks/<domain>/<name>.yaml`.** Mandatory fields:
   - `id`, `description`
   - `OOD: true|false` (true if the task is novel / resists memorization)
   - `resources: {guaranteed: 1x, ceiling: 3x}` — always declare both
   - `token_cap: {input: N, output: M}` — defense against runaway meta-reasoning
   - `trials: 3` minimum; 5 is better for stable pass@k / pass^k
   - `tracked_metrics: [...]` — turns, tool calls, tokens, TTFB, outcome.*, behavior.*
   - `graders: [...]` — one or more grader specs
   - `scoring_rule: binary_and | weighted_threshold | partial_credit`
   - `canary: "<unique-string>"` — for contamination detection
   - `cohort: <tag>` — for per-cohort segmentation in prod monitoring

3. **If LLM grader: write the rubric in `evals/rubrics/<name>.md`.** Dimensions, 0–10 scale, passing threshold, scoring formula. See `prd-quality.md` as the canonical example.

4. **Calibrate the LLM grader.** Drop 3 human-rated reference candidates into `evals/rubrics/calibration/<name>/`: a high-, a mid-, a low-score example. The grader uses them as few-shot context. Without this step the grader drifts.

5. **Run it.**
   ```bash
   python evals/harness/eval_runner.py evals/tasks/<domain>/<name>.yaml --trials 5
   ```

6. **Read the transcripts.** Aggregate metrics lie (Apr 23 postmortem proved this). Open `evals/results/<task-id>/<ts>/transcripts/` and skim at least 2 trials before trusting the score.

7. **Check the eval-awareness anomaly detector.**
   ```bash
   python evals/harness/anomaly.py evals/results/<task-id>/<ts>/
   ```
   Exits non-zero if any transcript shows meta-reasoning pivots (querying for "benchmark"/"canary"/etc.).

8. **Gate CI when stable.** Once the eval has passed 10+ runs without flake, add it to `.github/workflows/`.

## When to run the suite

| Trigger | What to run |
|---|---|
| Editing an agent definition under `.claude/agents/` | All `evals/tasks/agents/*.yaml` for that agent's cohort |
| Editing a hook | The hook's specific eval + the heartbeat |
| Editing a skill | The skill's eval (every skill should have one once stable) |
| Pre-deploy | The full suite + `cross_platform_eq.py` + `cohort_segment.py` |
| Continuous (cron) | `prod_monitor/continuous_quality.py --interval 1h` |

## Anti-patterns

- **Over-specifying tool-call paths.** Grade outcomes, not the exact sequence. (Demystifying-evals post)
- **Ambiguous specs.** If two SMEs disagree on the right answer, the spec is broken — fix the spec, not the grader.
- **Brittle string comparison.** `"96.12" != "96.124"` is a grader bug, not an agent failure.
- **Class imbalance.** Evals where every input is a positive case don't measure discriminative ability.
- **Saturation.** A task with 100% pass for 30 days has zero signal; rotate in harder cases.
- **Trusting aggregates.** Always look at `cohort_segment.py` output before declaring a regression or win.
- **No CI / no humans in the loop.** Evals are necessary, not sufficient. Read transcripts.

## Cost discipline

LLM graders cost money. Three knobs:

1. **`trials`** — minimum that gives a stable signal (3 if pass rate is bimodal, 5–10 otherwise).
2. **`token_cap`** — kills runaway agents; also kills runaway grader prompts.
3. **Caching** — the LLM grader's prompt is cacheable if the rubric and calibration are stable. Don't randomize across runs.

## Related skills

- `quality-monitor` — runs the suite continuously against prod
- `heartbeat` — liveness canary; pairs with eval suite for "alive + good"
- `contract-negotiation` — Dev/QA contract that drives many of the per-feature evals
