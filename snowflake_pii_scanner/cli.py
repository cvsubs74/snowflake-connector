"""Command-line interface: ``snowflake-pii-scan`` / ``python -m snowflake_pii_scanner``."""

from __future__ import annotations

import argparse
import logging
import sys

from .config import ConfigError, ScanScope, connect, connection_params_from_env
from .report import build_report, to_console, to_csv, to_json
from .scanner import scan


def _csv_list(value: str) -> list[str]:
    return [v.strip() for v in value.split(",") if v.strip()]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="snowflake-pii-scan",
        description="Identify Snowflake columns likely to contain PII. "
        "Credentials are read from SNOWFLAKE_* environment variables.",
    )
    parser.add_argument("--database", required=True, help="Database to scan")
    parser.add_argument(
        "--schemas", type=_csv_list, default=["*"], metavar="GLOB[,GLOB]",
        help="Schema name globs to include (default: all)",
    )
    parser.add_argument(
        "--tables", type=_csv_list, default=["*"], metavar="GLOB[,GLOB]",
        help="Table name globs to include (default: all)",
    )
    parser.add_argument(
        "--exclude-tables", type=_csv_list, default=[], metavar="GLOB[,GLOB]",
        help="Table name globs to exclude",
    )
    parser.add_argument(
        "--deep", action="store_true",
        help="Also profile values in-database (REGEXP_LIKE over a row sample; "
        "only aggregate match counts leave Snowflake)",
    )
    parser.add_argument(
        "--sample-rows", type=int, default=100,
        help="Rows sampled per table for --deep (default: 100)",
    )
    parser.add_argument(
        "--min-confidence", type=float, default=0.4,
        help="Report findings at or above this confidence, 0-1 (default: 0.4)",
    )
    parser.add_argument(
        "--format", choices=("json", "csv"), default="json",
        help="Export format for --output (default: json)",
    )
    parser.add_argument(
        "--output", metavar="PATH",
        help="Write the report to this file (console summary is always printed)",
    )
    parser.add_argument("-v", "--verbose", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.WARNING,
        format="%(levelname)s %(name)s: %(message)s",
    )

    scope = ScanScope(
        database=args.database,
        schemas=args.schemas,
        tables=args.tables,
        exclude_tables=args.exclude_tables,
        deep=args.deep,
        sample_rows=args.sample_rows,
        min_confidence=args.min_confidence,
    )

    try:
        params = connection_params_from_env()
    except ConfigError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    conn = connect(params)
    try:
        cursor = conn.cursor()
        try:
            findings = scan(cursor, scope)
        finally:
            cursor.close()
    finally:
        conn.close()

    report = build_report(findings, scope)
    print(to_console(report))

    if args.output:
        content = to_json(report) if args.format == "json" else to_csv(report)
        with open(args.output, "w", encoding="utf-8") as fh:
            fh.write(content)
        print(f"\nReport written to {args.output} ({args.format})")

    return 0


if __name__ == "__main__":
    sys.exit(main())
