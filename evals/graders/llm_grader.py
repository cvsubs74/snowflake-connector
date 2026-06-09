"""LLM-based graders: use Claude to judge quality against a rubric.

Use for quality judgments code can't make (is this PRD specific? is this review
actionable?). Always pair with a written rubric in `evals/rubrics/` and a
calibration set so the grader doesn't drift.

This module deliberately does not import the anthropic SDK at module-load time —
the harness imports it lazily so eval scaffolding works in environments without
the SDK installed.
"""

from __future__ import annotations

import json
import os
from pathlib import Path


def grade_with_rubric(
    candidate: str,
    rubric: str,
    model: str = "claude-opus-4-7",
    passing_threshold: float = 7.0,
    calibration_dir: str | None = None,
) -> dict:
    """Score `candidate` against the rubric at `rubric` path.

    Returns {score: 0|1, detail: str, raw_score: float}.
    """
    rubric_text = Path(rubric).read_text()
    calibration = _load_calibration(calibration_dir) if calibration_dir else ""

    prompt = _build_prompt(candidate, rubric_text, calibration)
    response_json = _call_claude(prompt, model)

    raw = float(response_json.get("score", 0))
    return {
        "score": 1 if raw >= passing_threshold else 0,
        "raw_score": raw,
        "detail": json.dumps(response_json, indent=2),
    }


def _build_prompt(candidate: str, rubric: str, calibration: str) -> str:
    return f"""You are grading a candidate artifact against a rubric.

<rubric>
{rubric}
</rubric>

{calibration}

<candidate>
{candidate}
</candidate>

Score the candidate. Return ONLY a JSON object with keys:
- score: float, the final score per the rubric's scoring formula
- per_dimension: object mapping each rubric dimension to its 0-10 score
- justification: string, one sentence per dimension

No prose outside the JSON.
"""


def _load_calibration(calibration_dir: str) -> str:
    """Load up to 3 calibration examples (high/mid/low) as few-shot context."""
    p = Path(calibration_dir)
    if not p.exists():
        return ""
    examples = []
    for name in sorted(p.glob("*.md"))[:3]:
        examples.append(f"<calibration_example name=\"{name.stem}\">\n{name.read_text()}\n</calibration_example>")
    return "\n".join(examples)


def _call_claude(prompt: str, model: str) -> dict:
    """Lazy-import the SDK; raise a friendly error if not installed."""
    try:
        from anthropic import Anthropic  # type: ignore
    except ImportError as e:
        raise RuntimeError(
            "anthropic SDK not installed. `pip install anthropic` to use LLM graders."
        ) from e

    client = Anthropic(api_key=os.environ.get("ANTHROPIC_API_KEY"))
    msg = client.messages.create(
        model=model,
        max_tokens=2000,
        messages=[{"role": "user", "content": prompt}],
    )
    text = msg.content[0].text if msg.content else "{}"
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return {"score": 0, "justification": f"grader returned non-JSON: {text[:500]}"}
