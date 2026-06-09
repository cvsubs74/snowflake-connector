from collections import defaultdict

from conftest import FakeCursor

from snowflake_pii_scanner.config import ScanScope
from snowflake_pii_scanner.rules import match_column_name
from snowflake_pii_scanner.scanner import (
    NAME_WEIGHT,
    CategoryFinding,
    build_probes,
    build_table_query,
    scan,
)

CATALOG = [
    ("PUBLIC", "CUSTOMERS", "EMAIL", "TEXT"),
    ("PUBLIC", "CUSTOMERS", "CONTACT", "TEXT"),
    ("PUBLIC", "CUSTOMERS", "ID", "NUMBER(38,0)"),
    ("PUBLIC", "CUSTOMERS", "CREATED_AT", "TIMESTAMP_NTZ"),
]


def _scope(**kw):
    return ScanScope(database="ANALYTICS", **kw)


def _name_findings(columns):
    findings = defaultdict(dict)
    for col in columns:
        for rule in match_column_name(col.column):
            findings[col][rule.category] = CategoryFinding(
                category=rule.category, confidence=NAME_WEIGHT, name_matched=True
            )
    return findings


def _deep_row(probes, ratios, total=100):
    """Build the aggregate row Snowflake would return for these probes."""
    row = [total]
    for p in probes:
        row.extend(ratios.get((p.column.column, p.category), (total, 0)))
    return tuple(row)


def test_metadata_scan_flags_named_columns_and_runs_one_query():
    cur = FakeCursor(catalog_rows=CATALOG)
    results = scan(cur, _scope())
    assert len(cur.queries) == 1  # information_schema only — no data queries
    flagged = {r.column.column: r.categories[0] for r in results}
    assert set(flagged) == {"EMAIL"}
    assert flagged["EMAIL"].category == "EMAIL"
    assert flagged["EMAIL"].confidence == NAME_WEIGHT
    assert flagged["EMAIL"].value_match_ratio is None


def test_deep_scan_skips_non_textual_columns():
    from snowflake_pii_scanner.catalog import fetch_columns

    cur = FakeCursor(catalog_rows=CATALOG)
    columns = fetch_columns(cur, _scope())
    probes = build_probes(columns, _name_findings(columns))
    assert "CREATED_AT" not in {p.column.column for p in probes}
    assert "ID" in {p.column.column for p in probes}  # numbers can hold SSNs/cards


def test_build_table_query_shape():
    from snowflake_pii_scanner.catalog import fetch_columns

    cur = FakeCursor(catalog_rows=CATALOG)
    columns = fetch_columns(cur, _scope())
    probes = build_probes(columns, _name_findings(columns))
    query = build_table_query(probes, _scope(deep=True, sample_rows=50))
    assert '"ANALYTICS"."PUBLIC"."CUSTOMERS"' in query
    assert "SAMPLE (50 ROWS)" in query
    assert "COUNT_IF(REGEXP_LIKE(TO_VARCHAR(" in query
    assert "$$" in query  # patterns embedded as dollar-quoted literals


def test_deep_scan_confidence_and_value_only_discovery():
    from snowflake_pii_scanner.catalog import fetch_columns

    setup = FakeCursor(catalog_rows=CATALOG)
    columns = fetch_columns(setup, _scope())
    probes = build_probes(columns, _name_findings(columns))
    row = _deep_row(probes, {
        ("EMAIL", "EMAIL"): (95, 90),     # name + values agree
        ("CONTACT", "EMAIL"): (100, 90),  # value-only discovery
        ("ID", "NATIONAL_ID"): (100, 10), # below MIN_VALUE_RATIO — dropped
    })

    cur = FakeCursor(catalog_rows=CATALOG, table_rows={"CUSTOMERS": row})
    results = scan(cur, _scope(deep=True))
    by_col = {r.column.column: r.categories[0] for r in results}

    email = by_col["EMAIL"]
    assert email.name_matched and email.value_match_ratio == 90 / 95
    assert abs(email.confidence - (0.6 + 0.4 * 90 / 95)) < 1e-9

    contact = by_col["CONTACT"]
    assert contact.category == "EMAIL" and not contact.name_matched
    assert abs(contact.confidence - 0.8 * 0.9) < 1e-3

    assert "ID" not in by_col


def test_deep_scan_table_error_keeps_name_findings():
    class FailingCursor(FakeCursor):
        def execute(self, query):
            if "INFORMATION_SCHEMA" not in query:
                raise RuntimeError("insufficient privileges")
            super().execute(query)

    cur = FailingCursor(catalog_rows=CATALOG)
    results = scan(cur, _scope(deep=True))
    assert {r.column.column for r in results} == {"EMAIL"}
    assert results[0].categories[0].confidence == NAME_WEIGHT


def test_min_confidence_filters_findings():
    cur = FakeCursor(catalog_rows=CATALOG)
    assert scan(cur, _scope(min_confidence=0.9)) == []
