# prod_monitor/ — continuous quality + cross-platform equivalence + cohort segmentation

These three scripts encode the postmortem-prevention defaults from the [Sept 2025 postmortem](https://www.anthropic.com/engineering/a-postmortem-of-three-recent-issues) and the [Apr 23 postmortem](https://www.anthropic.com/engineering/april-23-postmortem).

| Script | What it does | Why |
|---|---|---|
| `continuous_quality.py` | Runs the eval suite against the **live** system on a schedule (not a canary) | Routing bug in Sept 2025 grew from 0.8% → 16% because there was no continuous prod quality eval — only canary checks |
| `cross_platform_eq.py` | Asserts equivalent output across AWS / GCP / local | TPU character-corruption bug only manifested on one platform |
| `cohort_segment.py` | Segments metrics by user cohort, agent role, model version, region | Apr 23 postmortem: three independent changes each degraded a different traffic slice and masked each other in aggregate |

## How to run

```bash
# Continuous quality — schedule via `schedule` skill or cron.
python evals/prod_monitor/continuous_quality.py --interval 1h --tasks evals/tasks/

# Cross-platform — invoke per-deploy.
python evals/prod_monitor/cross_platform_eq.py --platforms aws,gcp,local

# Cohort segmentation — on any results dump.
python evals/prod_monitor/cohort_segment.py evals/results/
```

## Scripts here are scaffolds

The bodies are intentionally simple in the template — they show the *shape* (interfaces, expected I/O, exit codes). Wire them to your product's actual telemetry pipeline when you adopt this template into a real product.

The point is the **discipline**, not the code: never trust aggregate metrics, never assume cross-platform equivalence, never let prod quality drift between canary runs.
