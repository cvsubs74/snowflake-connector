# CLAUDE.md

This file provides guidance to [Claude Code](https://docs.anthropic.com/en/docs/claude-code) when working with code in this repository.

# snowflake-pii-scanner

A Python CLI that connects to Snowflake and identifies which columns are likely to contain PII, across 13 categories — **without raw data ever leaving Snowflake**.

## Required cold-start reading

Before acting on any goal, load:

1. `README.md` — what the scanner does, the two-tier detection model, all CLI flags, and the credentials contract.
2. `docs/PII_SCANNER.md` — design notes for the scanner.

## Architecture in one paragraph

A single Python ≥3.9 package, `snowflake_pii_scanner/`, exposing a CLI (`snowflake-pii-scan`, also `python -m snowflake_pii_scanner`). Its only runtime dependency is `snowflake-connector-python`, imported lazily. Detection is two-tier: a **metadata tier** matches `INFORMATION_SCHEMA` column names against per-category rules (`rules.py`), and an opt-in **deep tier** (`--deep`) pushes `REGEXP_LIKE` over a `SAMPLE (N ROWS)` *into the database* and returns only `COUNT_IF(...)` aggregates — sampled values are structurally prevented from leaving Snowflake. Authoritative modules: `snowflake_pii_scanner/{cli,config,catalog,scanner,rules,report}.py`. Credentials come only from environment variables (never CLI flags); sessions are tagged `QUERY_TAG=snowflake-pii-scanner`. No server, no deploy target — it's a CLI run against a Snowflake account.

## Common commands

```bash
# Install (editable, with test deps)
python3 -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"

# Tests — 65 tests, no Snowflake account or network needed (fake cursors)
python -m pytest

# Run the scanner (metadata-only — no table data leaves Snowflake)
snowflake-pii-scan --database ANALYTICS

# Deep scan (in-database value profiling)
snowflake-pii-scan --database ANALYTICS --deep --sample-rows 200 --output pii-report.json
```

## Coding discipline

Behavioral guidelines for code changes — bias toward caution over speed (use judgment on trivial tasks). Adapted from [karpathy/CLAUDE.md](https://github.com/multica-ai/andrej-karpathy-skills/blob/main/CLAUDE.md).

- **Think before coding.** State assumptions explicitly. If multiple interpretations exist, surface them — don't pick silently. If something is unclear, stop and name what's confusing rather than guessing. Push back when a simpler approach exists.
- **Simplicity first.** Minimum code that solves the problem. No features beyond what was asked, no abstractions for single-use code, no "flexibility" that wasn't requested, no error handling for impossible scenarios. If 200 lines could be 50, rewrite it. Ask: "would a senior engineer say this is overcomplicated?"
- **Surgical changes.** Touch only what the task requires. Don't "improve" adjacent code, comments, or formatting; don't refactor what isn't broken; match existing style even if you'd do it differently. Remove imports/variables your changes orphaned — leave pre-existing dead code alone (mention it, don't delete it). Every changed line should trace directly to the user's request.
- **Goal-driven execution.** Transform vague asks into verifiable success criteria before coding ("add validation" → "write tests for invalid inputs, then make them pass"; "fix the bug" → "write a test that reproduces it, then make it pass"). For multi-step work, state a brief plan with explicit verify-checks per step.
- **Evidence before assertions.** Never claim "done" / "fixed" / "complete" without verification — run `python -m pytest` and report the result.
- **Privacy is the core invariant.** This tool exists so PII *stays inside Snowflake*. Never add a code path that transfers, logs, or writes sampled cell values out of the database — `--deep` returns aggregate counts only, and reports carry identifiers + statistics, never values. Any change touching `scanner.py`/`report.py` must preserve this.

## Agent team (`.claude/`)

The `.claude/` directory still defines a multi-agent engineering team (agents, slash commands, hooks, skills) — spawn it with `/onboard-team`. Note: the team's supporting scaffolding (`ETHOS.md`, `SDLC.md`, `bin/`, `memory/`, `docs/contracts/`, `docs/playbooks/`, eval/MCP harness) was removed when this repo was trimmed to the scanner, so some agents, hooks, and slash commands reference files that no longer exist and will run degraded. Restore them from git history if you want the full harness back.
