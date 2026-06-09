#!/usr/bin/env python3
"""Cohort segmentation report.

Apr 23 postmortem: three independent changes each degraded a different traffic
slice and masked each other in aggregate. The defense is to never look at one
number — always segment.

Walks results/, groups by cohort tag, prints per-cohort pass rate + CI.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path
from statistics import mean


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("results_dir", help="evals/results/ or a single task's results")
    args = ap.parse_args()

    metrics_files = list(Path(args.results_dir).rglob("metrics.json"))
    by_cohort = defaultdict(list)
    for f in metrics_files:
        try:
            m = json.loads(f.read_text())
            cohort = m.get("cohort") or "uncategorized"
            by_cohort[cohort].append(m.get("p_per_trial", 0.0))
        except (json.JSONDecodeError, OSError):
            continue

    print(f"{'cohort':<30} {'n':>5} {'mean_pass':>10} {'min':>6} {'max':>6}")
    print("-" * 60)
    for cohort, rates in sorted(by_cohort.items()):
        print(
            f"{cohort:<30} {len(rates):>5} {mean(rates):>10.3f} {min(rates):>6.2f} {max(rates):>6.2f}"
        )
    if not by_cohort:
        print("(no metrics found)")


if __name__ == "__main__":
    main()
