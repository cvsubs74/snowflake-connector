"""State-based graders: did the world end up in the expected state?

Verify outcomes against the filesystem, a database, or a UI snapshot.
For UI verification, prefer the Playwright MCP via the `verify` skill.
"""

from __future__ import annotations

import json
from pathlib import Path


def json_field_equals(path: str, jq_path: str, expected) -> dict:
    """Pass iff JSON at `path` has value `expected` at dotted `jq_path`."""
    p = Path(path)
    if not p.exists():
        return {"score": 0, "detail": f"file missing: {path}"}
    try:
        data = json.loads(p.read_text())
    except json.JSONDecodeError as e:
        return {"score": 0, "detail": f"invalid JSON in {path}: {e}"}
    cursor = data
    for key in jq_path.split("."):
        if isinstance(cursor, dict) and key in cursor:
            cursor = cursor[key]
        else:
            return {"score": 0, "detail": f"path {jq_path} missing in {path}"}
    ok = cursor == expected
    return {
        "score": 1 if ok else 0,
        "detail": f"{jq_path}: expected {expected!r}, got {cursor!r}",
    }


def file_count_in_dir(dir: str, pattern: str, expected_min: int = 1) -> dict:
    """Pass iff dir contains at least `expected_min` files matching `pattern`."""
    matches = list(Path(dir).glob(pattern))
    return {
        "score": 1 if len(matches) >= expected_min else 0,
        "detail": f"{len(matches)} files match {pattern} in {dir} (need >={expected_min})",
    }
