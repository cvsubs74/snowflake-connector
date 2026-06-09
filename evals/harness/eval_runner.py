#!/usr/bin/env python3
"""Eval runner: run a task N times in a clean env, compute pass@k + pass^k, save transcripts.

Usage:
  python evals/harness/eval_runner.py evals/tasks/agents/prd-quality.yaml [--trials 5]

Outputs:
  evals/results/<task-id>/<utc-timestamp>/transcripts/trial-<i>.json
  evals/results/<task-id>/<utc-timestamp>/metrics.json

This harness is deliberately minimal — it loads a task spec, invokes the configured
graders, and aggregates results. It does NOT itself drive an agent session; the
agent's transcript is expected to be produced separately (by a Claude Code session,
a headless `claude -p` run, or whatever the task's `runner` field specifies).

Per the Quantifying infrastructure noise post, infra noise can exceed model-to-model
gaps. Treat <3pp leaderboard differences as noise unless reported with binomial CI.
"""

from __future__ import annotations

import argparse
import importlib
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from statistics import mean

try:
    import yaml  # type: ignore
except ImportError:
    print("ERROR: pyyaml not installed. `pip install pyyaml`.", file=sys.stderr)
    sys.exit(2)


REPO_ROOT = Path(__file__).resolve().parents[2]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("task_path", help="Path to eval task YAML")
    ap.add_argument("--trials", type=int, default=None, help="Override trial count")
    ap.add_argument(
        "--transcript-dir",
        default=None,
        help="Directory of pre-generated transcripts (one per trial) to grade. "
        "If omitted, the harness records the eval was *attempted* but skips grading.",
    )
    args = ap.parse_args()

    task = yaml.safe_load(Path(args.task_path).read_text())
    trials = args.trials or task.get("trials", 3)
    task_id = task["id"]
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out_dir = REPO_ROOT / "evals" / "results" / task_id / ts
    (out_dir / "transcripts").mkdir(parents=True, exist_ok=True)

    print(f"[eval-runner] task={task_id} trials={trials} out={out_dir}")

    # Per-trial grading.
    trial_results = []
    for i in range(trials):
        transcript_path = (
            Path(args.transcript_dir) / f"trial-{i}.json"
            if args.transcript_dir
            else None
        )
        candidate_text = (
            transcript_path.read_text() if transcript_path and transcript_path.exists() else ""
        )
        grades = run_graders(task, candidate_text)
        trial_results.append(
            {
                "trial": i,
                "transcript_path": str(transcript_path) if transcript_path else None,
                "grades": grades,
                "passed": combine_scores(grades, task.get("scoring_rule", "binary_and")),
            }
        )
        # Save transcript copy alongside metrics for reproducibility.
        if candidate_text:
            (out_dir / "transcripts" / f"trial-{i}.txt").write_text(candidate_text)

    # Aggregate.
    passes = sum(1 for r in trial_results if r["passed"])
    pass_at_k = 1.0 if passes >= 1 else 0.0
    pass_pow_k = 1.0 if passes == trials else 0.0
    p_per_trial = passes / trials if trials else 0.0
    # 95% Wilson CI on per-trial pass rate for honest reporting.
    ci_lo, ci_hi = wilson_ci(passes, trials)

    metrics = {
        "task_id": task_id,
        "timestamp_utc": ts,
        "trials": trials,
        "passes": passes,
        "p_per_trial": p_per_trial,
        "pass@k": pass_at_k,
        "pass^k": pass_pow_k,
        "wilson_ci_95": [ci_lo, ci_hi],
        "cohort": task.get("cohort"),
        "ood": task.get("OOD", False),
        "trial_results": trial_results,
    }
    (out_dir / "metrics.json").write_text(json.dumps(metrics, indent=2))

    print(
        f"[eval-runner] {passes}/{trials} passed · "
        f"pass@k={pass_at_k:.2f} pass^k={pass_pow_k:.2f} "
        f"p_per_trial={p_per_trial:.2f} [CI: {ci_lo:.2f}, {ci_hi:.2f}]"
    )
    print(f"[eval-runner] results → {out_dir}/metrics.json")


def run_graders(task: dict, candidate: str) -> list[dict]:
    results = []
    for g in task.get("graders", []):
        try:
            mod = importlib.import_module(g["module"])
            fn = getattr(mod, g["function"])
            args = dict(g.get("args", {}))
            # llm graders take the candidate; code/state graders may not need it.
            if g.get("type") == "llm":
                args["candidate"] = candidate
            res = fn(**args)
            results.append({"id": g["id"], "type": g["type"], **res})
        except Exception as e:
            results.append({"id": g["id"], "type": g["type"], "score": 0, "detail": f"grader error: {e}"})
    return results


def combine_scores(grades: list[dict], rule: str) -> bool:
    if not grades:
        return False
    scores = [g.get("score", 0) for g in grades]
    if rule == "binary_and":
        return all(s == 1 for s in scores)
    if rule == "weighted_threshold":
        return mean(scores) >= 0.5
    if rule == "partial_credit":
        return mean(scores) >= 0.5
    return all(s == 1 for s in scores)


def wilson_ci(successes: int, trials: int, z: float = 1.96) -> tuple[float, float]:
    """Wilson score 95% CI on a binomial proportion. Honest reporting for small n."""
    if trials == 0:
        return (0.0, 0.0)
    p = successes / trials
    n = trials
    denom = 1 + z**2 / n
    center = (p + z**2 / (2 * n)) / denom
    margin = z * ((p * (1 - p) / n + z**2 / (4 * n**2)) ** 0.5) / denom
    return (max(0.0, center - margin), min(1.0, center + margin))


if __name__ == "__main__":
    sys.path.insert(0, str(REPO_ROOT / "evals"))
    main()
