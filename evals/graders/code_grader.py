"""Code-based graders: deterministic outcome checks.

Use for things you can verify with file I/O, shell commands, or static analysis.
Returns: dict {score: 0|1, detail: str}.
"""

from __future__ import annotations

import glob
import os
import subprocess
from pathlib import Path


def file_exists_in_dir(dir: str, pattern: str, base: str = ".") -> dict:
    """Pass iff at least one file matching `pattern` exists in `dir` under `base`."""
    search = os.path.join(base, dir, pattern)
    matches = glob.glob(search)
    return {
        "score": 1 if matches else 0,
        "detail": f"matched {len(matches)} files at {search}: {matches[:3]}",
    }


def shell_command_succeeds(cmd: str, cwd: str = ".", timeout: int = 60) -> dict:
    """Pass iff `cmd` exits 0. cmd runs through shell — caller controls quoting."""
    try:
        result = subprocess.run(
            cmd, shell=True, cwd=cwd, capture_output=True, text=True, timeout=timeout
        )
        return {
            "score": 1 if result.returncode == 0 else 0,
            "detail": f"rc={result.returncode}\nstdout: {result.stdout[:500]}\nstderr: {result.stderr[:500]}",
        }
    except subprocess.TimeoutExpired:
        return {"score": 0, "detail": f"timeout after {timeout}s"}


def file_contains(path: str, needle: str) -> dict:
    """Pass iff `needle` appears in `path`."""
    p = Path(path)
    if not p.exists():
        return {"score": 0, "detail": f"file missing: {path}"}
    content = p.read_text(errors="replace")
    return {
        "score": 1 if needle in content else 0,
        "detail": f"needle {'found' if needle in content else 'absent'} in {path}",
    }
