"""Scan orchestration.

The deep scan never pulls values out of Snowflake: for each table it issues a
single aggregate query of the form

    SELECT COUNT(*),
           COUNT("COL"), COUNT_IF(REGEXP_LIKE(TO_VARCHAR("COL"), $$pattern$$)),
           ...
    FROM "DB"."SCHEMA"."TABLE" SAMPLE (100 ROWS)

so only row counts ever cross the wire. Patterns are embedded as
dollar-quoted literals to avoid backslash-escaping pitfalls.
"""

from __future__ import annotations

import logging
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Optional

from .catalog import ColumnInfo, fetch_columns, quote_ident
from .config import ScanScope
from .rules import TEXTUAL_TYPES, match_column_name, rule_for, value_only_rules

logger = logging.getLogger("snowflake_pii_scanner")

# Confidence model: a column-name match alone scores NAME_WEIGHT; a value-match
# ratio r adds VALUE_WEIGHT * r when the name also matched, and scores
# VALUE_ONLY_WEIGHT * r on its own.
NAME_WEIGHT = 0.6
VALUE_WEIGHT = 0.4
VALUE_ONLY_WEIGHT = 0.8

# Don't report a value-only match unless this share of sampled non-null
# values matched — guards against incidental pattern hits.
MIN_VALUE_RATIO = 0.3


@dataclass
class CategoryFinding:
    category: str
    confidence: float
    name_matched: bool
    value_match_ratio: Optional[float] = None  # None = values not profiled
    sampled_rows: Optional[int] = None


@dataclass
class ColumnFinding:
    column: ColumnInfo
    categories: list[CategoryFinding] = field(default_factory=list)


def scan(cursor, scope: ScanScope) -> list[ColumnFinding]:
    """Run the scan and return findings above the scope's confidence floor."""
    columns = fetch_columns(cursor, scope)
    logger.info("Scanning %d columns in scope", len(columns))

    findings: dict[ColumnInfo, dict[str, CategoryFinding]] = defaultdict(dict)
    for col in columns:
        for rule in match_column_name(col.column):
            findings[col][rule.category] = CategoryFinding(
                category=rule.category, confidence=NAME_WEIGHT, name_matched=True
            )

    if scope.deep:
        _deep_scan(cursor, columns, findings, scope)

    results = []
    for col in columns:
        kept = [
            f for f in findings.get(col, {}).values()
            if f.confidence >= scope.min_confidence
        ]
        if kept:
            kept.sort(key=lambda f: f.confidence, reverse=True)
            results.append(ColumnFinding(column=col, categories=kept))
    return results


@dataclass(frozen=True)
class _Probe:
    column: ColumnInfo
    category: str
    pattern: str
    name_matched: bool


def build_probes(columns: list[ColumnInfo], findings) -> list[_Probe]:
    """Decide which column x value-pattern pairs to profile in-database."""
    probes = []
    for col in columns:
        base_type = col.data_type.split("(")[0].strip().upper()
        if base_type not in TEXTUAL_TYPES:
            continue
        named = findings.get(col, {})
        # Verify value patterns for categories the column name suggested.
        for category, f in named.items():
            rule = rule_for(category)
            if f.name_matched and rule.value_pattern:
                probes.append(_Probe(col, category, rule.value_pattern, True))
        # Try high-precision patterns against every textual column.
        for rule in value_only_rules():
            if rule.category not in named:
                probes.append(_Probe(col, rule.category, rule.value_pattern, False))
    return probes


def build_table_query(table_cols: list[_Probe], scope: ScanScope) -> str:
    col0 = table_cols[0].column
    table_ref = ".".join(
        quote_ident(p) for p in (col0.database, col0.schema, col0.table)
    )
    exprs = ["COUNT(*) AS total_rows"]
    for probe in table_cols:
        qcol = quote_ident(probe.column.column)
        exprs.append(f"COUNT({qcol})")
        exprs.append(f"COUNT_IF(REGEXP_LIKE(TO_VARCHAR({qcol}), $${probe.pattern}$$))")
    return (
        "SELECT " + ", ".join(exprs)
        + f" FROM {table_ref} SAMPLE ({scope.sample_rows} ROWS)"
    )


def _deep_scan(cursor, columns, findings, scope: ScanScope) -> None:
    probes = build_probes(columns, findings)
    by_table: dict[tuple, list[_Probe]] = defaultdict(list)
    for probe in probes:
        c = probe.column
        by_table[(c.database, c.schema, c.table)].append(probe)

    for table_key, table_probes in by_table.items():
        query = build_table_query(table_probes, scope)
        try:
            cursor.execute(query)
            row = cursor.fetchone()
        except Exception as exc:  # e.g. no SELECT privilege on one table
            logger.warning("Deep scan skipped for %s.%s.%s: %s", *table_key, exc)
            continue
        _apply_row(row, table_probes, findings)


def _apply_row(row, table_probes: list[_Probe], findings) -> None:
    # Row layout: total_rows, then (non_null, matched) per probe.
    for i, probe in enumerate(table_probes):
        non_null, matched = row[1 + 2 * i], row[2 + 2 * i]
        ratio = (matched / non_null) if non_null else 0.0
        existing = findings[probe.column].get(probe.category)
        if probe.name_matched and existing is not None:
            existing.value_match_ratio = ratio
            existing.sampled_rows = non_null
            existing.confidence = min(1.0, NAME_WEIGHT + VALUE_WEIGHT * ratio)
        elif ratio >= MIN_VALUE_RATIO:
            findings[probe.column][probe.category] = CategoryFinding(
                category=probe.category,
                confidence=round(VALUE_ONLY_WEIGHT * ratio, 4),
                name_matched=False,
                value_match_ratio=ratio,
                sampled_rows=non_null,
            )
