---
description: Run the eval suite (or a single task) and report per-cohort results. Use after editing an agent, hook, or skill — and before any deploy.
---

# /eval — run evals and report

## Usage

- `/eval` — run the full suite under `evals/tasks/`
- `/eval agents/prd-quality` — run a single task
- `/eval --cohort agent.pm` — run all tasks tagged for the pm cohort
- `/eval --trials 10 <task>` — override trial count

## What this command does

1. Reads `memory/PROGRESS.md` to identify what changed (so we know which cohorts to focus on).
2. Resolves the task selector (single task / cohort / suite).
3. Invokes `python evals/harness/eval_runner.py` for each task — clean env per trial, pass@k + pass^k, 95% Wilson CI on per-trial rate.
4. Runs `python evals/harness/anomaly.py` over the new transcripts — flags eval-awareness signals.
5. Runs `python evals/prod_monitor/cohort_segment.py evals/results/` — per-cohort report.
6. Compares per-cohort pass rate to the previous run; flags any drop >3pp as soft regression, >10pp as hard.
7. Posts the cohort table + flagged transcripts back to the operator.

## Output format

```
COHORT TABLE
cohort                     n  mean_pass    min    max    Δ-vs-prev
agent.pm                   5      0.800   0.60   1.00      -0.10  ⚠
agent.dev                  5      0.920   0.80   1.00      +0.02
agent.qa                   5      0.760   0.60   0.80      +0.00
ui.golden-path             3      1.000   1.00   1.00      +0.00

SOFT REGRESSION: agent.pm dropped 0.10 (prev 0.90, now 0.80) — investigate
ANOMALY: 0 transcripts flagged for eval-awareness signals
```

## Defaults

- **Trials**: per-task setting (usually 3 or 5). Override with `--trials`.
- **Concurrency**: serial by default. `--parallel N` to fan out (be careful with infra noise — re-read the infra-noise post).
- **Output**: written to `evals/results/<task-id>/<utc-ts>/`. Transcripts are kept; read them.

## When NOT to use

- For one-off smoke tests, use `/heartbeat` (cheaper, faster, no per-cohort breakdown).
- For UI verification of a specific change, use `/verify` (Playwright-driven, single-shot).
- For a deep dive into a single regression, use `/investigate` (root-cause discipline, not aggregate metrics).

## Related

- `eval-runner` skill — how to *add* an eval
- `quality-monitor` skill — continuous prod variant of this command
- `heartbeat` skill — liveness canary
