---
name: quality-monitor
description: Use when setting up continuous prod quality monitoring, investigating a quality regression, or interpreting cohort-segmented metrics. Encodes the postmortem-prevention defaults — never trust aggregate metrics, always segment, always check cross-platform.
---

# quality-monitor — continuous prod quality + regression triage

Two failure modes this skill defends against:

1. **The Sept 2025 routing bug**: aggregate metrics looked fine; 16% of requests were silently misrouted because monitoring only checked a canary.
2. **The Apr 23 quality regression**: three independent changes each degraded a different traffic slice and masked each other.

The fix in both cases is the same: **continuous prod evals + cohort segmentation + cross-platform equivalence**.

## Setup checklist

1. **Schedule the continuous quality monitor.**
   ```bash
   # via the schedule skill (preferred), or cron, or claude --loop
   python evals/prod_monitor/continuous_quality.py --interval 1h --tasks evals/tasks/
   ```

2. **Wire cohort tags into eval task YAMLs.** Every task must declare `cohort: <segment>` (e.g., `agent.pm`, `user.enterprise`, `region.eu-west-1`).

3. **Run `cohort_segment.py` after every batch.**
   ```bash
   python evals/prod_monitor/cohort_segment.py evals/results/
   ```
   Per-cohort pass rate, min, max. **Look at this, not at the aggregate.**

4. **Pre-deploy: cross-platform equivalence.**
   ```bash
   python evals/prod_monitor/cross_platform_eq.py --platforms aws,gcp,local
   ```
   The Sept 2025 TPU bug (Thai characters in English responses) only manifested on one platform.

## Regression triage workflow

When a cohort's pass rate drops:

1. **Don't trust one data point.** Pull the last 7 runs for that cohort.
2. **Correlate with deploy timeline.** `git log --since="<earliest-bad-run>"` — what changed?
3. **Read transcripts.** Aggregate metrics tell you *something* changed; transcripts tell you *what*.
4. **Check workaround-audit log.** If anyone removed a `# WORKAROUND` comment recently, suspect it.
5. **Ablate.** If multiple PRs land in the suspect window, revert them one at a time and re-run. The XLA top-k bug from Sept 2025 was hidden behind a workaround that someone had removed.

## Alert thresholds

- **Per-cohort pass rate drops >3pp run-over-run** → soft alert, investigate within 24h
- **Per-cohort pass rate drops >10pp** → hard alert, page on-call
- **Any character-script anomaly from `cross_platform_eq.py`** → hard alert, this is the TPU-bug signature
- **Eval-awareness anomaly from `harness/anomaly.py`** → soft alert, dataset contamination suspected; rotate canary strings

## What this skill does NOT do

- Replace the existing `/heartbeat` skill — heartbeat = liveness, quality-monitor = quality. Both needed.
- Catch every regression — only the ones your eval suite covers. Coverage gaps are real; the eval set must grow when prod surfaces a new failure mode.
- Detect novel failure types automatically — only those that match the cohort or character-script signature. New failure classes need new graders.

## Related skills

- `eval-runner` — the harness underneath
- `heartbeat` — the liveness canary
- `investigate` — when a regression needs a root-cause sprint
