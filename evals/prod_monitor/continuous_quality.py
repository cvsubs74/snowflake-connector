#!/usr/bin/env python3
"""Continuous quality monitor — run eval suite against live system, not canary.

Scaffold. Wire to your product's actual run path. The shape is:
  load tasks → for each, drive the live system → grade → emit metrics + alert on regression.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--interval", default="1h", help="Run interval (1m|10m|1h|6h|24h)")
    ap.add_argument("--tasks", default="evals/tasks/", help="Tasks dir")
    ap.add_argument("--once", action="store_true", help="Single run then exit")
    args = ap.parse_args()

    interval_s = parse_interval(args.interval)
    while True:
        run_one_cycle(args.tasks)
        if args.once:
            return
        time.sleep(interval_s)


def run_one_cycle(tasks_dir: str):
    """Single pass: enumerate task YAMLs, invoke eval_runner per task."""
    tasks = list((REPO_ROOT / tasks_dir).rglob("*.yaml"))
    print(f"[prod-monitor] {len(tasks)} tasks, cycle start")
    for t in tasks:
        cmd = ["python", str(REPO_ROOT / "evals/harness/eval_runner.py"), str(t)]
        try:
            subprocess.run(cmd, check=False, timeout=600)
        except subprocess.TimeoutExpired:
            print(f"[prod-monitor] TIMEOUT on {t.name}", file=sys.stderr)
    print(f"[prod-monitor] cycle done")


def parse_interval(s: str) -> int:
    units = {"s": 1, "m": 60, "h": 3600, "d": 86400}
    if not s or s[-1] not in units:
        raise ValueError(f"bad interval: {s}")
    return int(s[:-1]) * units[s[-1]]


if __name__ == "__main__":
    main()
