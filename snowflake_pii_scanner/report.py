"""Report building and export. Reports contain identifiers, categories, and
aggregate statistics only — never sampled values."""

from __future__ import annotations

import csv
import io
import json
from datetime import datetime, timezone

from . import __version__
from .config import ScanScope
from .scanner import ColumnFinding

CSV_FIELDS = (
    "database", "schema", "table", "column", "data_type",
    "category", "confidence", "name_matched", "value_match_ratio", "sampled_rows",
)


def build_report(findings: list[ColumnFinding], scope: ScanScope) -> dict:
    return {
        "scanner_version": __version__,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "scope": {
            "database": scope.database,
            "schemas": scope.schemas,
            "tables": scope.tables,
            "exclude_tables": scope.exclude_tables,
            "deep": scope.deep,
            "sample_rows": scope.sample_rows if scope.deep else None,
            "min_confidence": scope.min_confidence,
        },
        "summary": {
            "columns_flagged": len(findings),
            "tables_flagged": len(
                {(f.column.schema, f.column.table) for f in findings}
            ),
        },
        "findings": [_finding_dict(f) for f in findings],
    }


def _finding_dict(f: ColumnFinding) -> dict:
    c = f.column
    return {
        "database": c.database,
        "schema": c.schema,
        "table": c.table,
        "column": c.column,
        "data_type": c.data_type,
        "categories": [
            {
                "category": cat.category,
                "confidence": round(cat.confidence, 4),
                "name_matched": cat.name_matched,
                "value_match_ratio": cat.value_match_ratio,
                "sampled_rows": cat.sampled_rows,
            }
            for cat in f.categories
        ],
    }


def to_json(report: dict) -> str:
    return json.dumps(report, indent=2)


def to_csv(report: dict) -> str:
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=CSV_FIELDS, lineterminator="\n")
    writer.writeheader()
    for finding in report["findings"]:
        for cat in finding["categories"]:
            writer.writerow({
                "database": finding["database"],
                "schema": finding["schema"],
                "table": finding["table"],
                "column": finding["column"],
                "data_type": finding["data_type"],
                "category": cat["category"],
                "confidence": cat["confidence"],
                "name_matched": cat["name_matched"],
                "value_match_ratio": cat["value_match_ratio"],
                "sampled_rows": cat["sampled_rows"],
            })
    return buf.getvalue()


def to_console(report: dict) -> str:
    lines = [
        f"Snowflake PII scan — database {report['scope']['database']}",
        f"  columns flagged: {report['summary']['columns_flagged']}"
        f"  (across {report['summary']['tables_flagged']} tables)",
        "",
    ]
    if not report["findings"]:
        lines.append("No likely PII columns found in scope.")
        return "\n".join(lines)

    rows = []
    for finding in report["findings"]:
        top = finding["categories"][0]
        rows.append((
            f"{finding['schema']}.{finding['table']}.{finding['column']}",
            top["category"],
            f"{top['confidence']:.2f}",
            "name+values" if top["value_match_ratio"] is not None and top["name_matched"]
            else ("values" if top["value_match_ratio"] is not None else "name"),
        ))
    widths = [max(len(r[i]) for r in rows + [("COLUMN", "CATEGORY", "CONF", "EVIDENCE")])
              for i in range(4)]
    header = ("COLUMN", "CATEGORY", "CONF", "EVIDENCE")
    for row in [header] + rows:
        lines.append("  ".join(cell.ljust(widths[i]) for i, cell in enumerate(row)))
    return "\n".join(lines)
