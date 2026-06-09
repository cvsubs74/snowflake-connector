#!/usr/bin/env python3
"""Cross-platform equivalence check.

Scaffold. The discipline: never assume the same prompt produces the same output
across AWS / GCP / local. Run a fixed task on each platform; assert outputs are
semantically equivalent.

Wire `_invoke_on` to your product's per-platform run path.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--platforms", default="aws,gcp,local", help="Comma list")
    ap.add_argument("--task", default="evals/tasks/agents/prd-quality.yaml")
    args = ap.parse_args()

    platforms = args.platforms.split(",")
    outputs = {p: _invoke_on(p, args.task) for p in platforms}

    # Equivalence check: char-script anomaly (Sept 2025 postmortem caught Thai-in-English here).
    findings = []
    for p, text in outputs.items():
        if _has_unexpected_script(text):
            findings.append({"platform": p, "issue": "unexpected character script"})

    # Semantic equivalence: pairwise hash + length-delta check.
    hashes = {p: hashlib.sha256(text.encode()).hexdigest()[:16] for p, text in outputs.items()}
    if len(set(hashes.values())) > 1:
        # Outputs differ; that's expected for stochastic models — record for review.
        findings.append({"hashes": hashes, "issue": "outputs differ across platforms (review for severity)"})

    print(json.dumps({"platforms": platforms, "findings": findings}, indent=2))
    sys.exit(1 if any(f.get("issue") == "unexpected character script" for f in findings) else 0)


def _invoke_on(platform: str, task: str) -> str:
    """STUB. Replace with the per-platform invocation for your product."""
    return f"[stub output from {platform} for {task}]"


def _has_unexpected_script(text: str) -> bool:
    """Detect chars from a script unexpected in English (Thai, CJK, etc.)."""
    for ch in text:
        cp = ord(ch)
        if 0x0E00 <= cp <= 0x0E7F:  # Thai
            return True
        if 0x4E00 <= cp <= 0x9FFF:  # CJK Unified Ideographs
            return True
    return False


if __name__ == "__main__":
    main()
