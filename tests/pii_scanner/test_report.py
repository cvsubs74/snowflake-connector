import csv
import io
import json

from snowflake_pii_scanner.catalog import ColumnInfo
from snowflake_pii_scanner.config import ScanScope
from snowflake_pii_scanner.report import build_report, to_console, to_csv, to_json
from snowflake_pii_scanner.scanner import CategoryFinding, ColumnFinding

FINDINGS = [
    ColumnFinding(
        column=ColumnInfo("ANALYTICS", "PUBLIC", "CUSTOMERS", "EMAIL", "TEXT"),
        categories=[CategoryFinding("EMAIL", 0.95, True, 0.9, 100)],
    ),
    ColumnFinding(
        column=ColumnInfo("ANALYTICS", "PUBLIC", "CUSTOMERS", "PHONE", "TEXT"),
        categories=[CategoryFinding("PHONE", 0.6, True)],
    ),
]

SCOPE = ScanScope(database="ANALYTICS", deep=True)


def test_report_structure_and_json_round_trip():
    report = build_report(FINDINGS, SCOPE)
    assert report["summary"] == {"columns_flagged": 2, "tables_flagged": 1}
    assert report["scope"]["database"] == "ANALYTICS"
    parsed = json.loads(to_json(report))
    assert parsed["findings"][0]["column"] == "EMAIL"
    assert parsed["findings"][0]["categories"][0]["confidence"] == 0.95


def test_report_contains_no_sampled_values():
    # The report model has no field that could carry values; double-check the
    # serialized output only references identifiers and statistics.
    text = to_json(build_report(FINDINGS, SCOPE))
    for forbidden in ("sample_values", "examples", "@"):
        assert forbidden not in text


def test_csv_one_row_per_column_category():
    report = build_report(FINDINGS, SCOPE)
    rows = list(csv.DictReader(io.StringIO(to_csv(report))))
    assert len(rows) == 2
    assert rows[0]["table"] == "CUSTOMERS"
    assert rows[0]["category"] == "EMAIL"
    assert rows[1]["value_match_ratio"] == ""  # not profiled


def test_console_summary_lists_findings():
    out = to_console(build_report(FINDINGS, SCOPE))
    assert "PUBLIC.CUSTOMERS.EMAIL" in out
    assert "name+values" in out
    assert "columns flagged: 2" in out


def test_console_summary_empty():
    out = to_console(build_report([], SCOPE))
    assert "No likely PII columns" in out
