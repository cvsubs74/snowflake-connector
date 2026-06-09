from conftest import FakeCursor

from snowflake_pii_scanner.catalog import fetch_columns, quote_ident
from snowflake_pii_scanner.config import ScanScope

ROWS = [
    ("PUBLIC", "CUSTOMERS", "EMAIL", "TEXT"),
    ("PUBLIC", "CUSTOMERS", "ID", "NUMBER(38,0)"),
    ("PUBLIC", "TMP_LOAD", "EMAIL", "TEXT"),
    ("SALES", "ORDERS", "TOTAL", "NUMBER(10,2)"),
]


def test_fetch_columns_queries_information_schema():
    cur = FakeCursor(catalog_rows=ROWS)
    cols = fetch_columns(cur, ScanScope(database="ANALYTICS"))
    assert len(cols) == 4
    query = cur.queries[0]
    assert '"ANALYTICS".INFORMATION_SCHEMA.COLUMNS' in query
    assert "table_type = 'BASE TABLE'" in query
    assert cols[0].database == "ANALYTICS"
    assert cols[0].column == "EMAIL"


def test_schema_and_table_scope_filters():
    cur = FakeCursor(catalog_rows=ROWS)
    scope = ScanScope(database="ANALYTICS", schemas=["public"],
                      exclude_tables=["TMP_*"])
    cols = fetch_columns(cur, scope)
    assert {(c.schema, c.table) for c in cols} == {("PUBLIC", "CUSTOMERS")}


def test_table_include_globs():
    cur = FakeCursor(catalog_rows=ROWS)
    scope = ScanScope(database="ANALYTICS", tables=["ORD*"])
    cols = fetch_columns(cur, scope)
    assert {c.table for c in cols} == {"ORDERS"}


def test_quote_ident_escapes_quotes():
    assert quote_ident('we"ird') == '"we""ird"'
    assert quote_ident("CUSTOMERS") == '"CUSTOMERS"'
