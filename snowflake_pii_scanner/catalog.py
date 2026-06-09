"""Read column metadata from INFORMATION_SCHEMA and apply the scan scope."""

from __future__ import annotations

import fnmatch
from dataclasses import dataclass

from .config import ScanScope


@dataclass(frozen=True)
class ColumnInfo:
    database: str
    schema: str
    table: str
    column: str
    data_type: str


def quote_ident(name: str) -> str:
    """Quote a Snowflake identifier, escaping embedded double quotes."""
    return '"' + name.replace('"', '""') + '"'


def fetch_columns(cursor, scope: ScanScope) -> list[ColumnInfo]:
    """Return columns of base tables in scope, in catalog order."""
    query = (
        "SELECT c.table_schema, c.table_name, c.column_name, c.data_type\n"
        f"FROM {quote_ident(scope.database)}.INFORMATION_SCHEMA.COLUMNS c\n"
        f"JOIN {quote_ident(scope.database)}.INFORMATION_SCHEMA.TABLES t\n"
        "  ON c.table_schema = t.table_schema AND c.table_name = t.table_name\n"
        "WHERE t.table_type = 'BASE TABLE'\n"
        "  AND c.table_schema <> 'INFORMATION_SCHEMA'\n"
        "ORDER BY c.table_schema, c.table_name, c.ordinal_position"
    )
    cursor.execute(query)
    columns = [
        ColumnInfo(scope.database, schema, table, column, data_type)
        for schema, table, column, data_type in cursor.fetchall()
    ]
    return [c for c in columns if _in_scope(c, scope)]


def _matches_any(name: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatch(name.lower(), p.lower()) for p in patterns)


def _in_scope(col: ColumnInfo, scope: ScanScope) -> bool:
    if not _matches_any(col.schema, scope.schemas):
        return False
    if not _matches_any(col.table, scope.tables):
        return False
    if scope.exclude_tables and _matches_any(col.table, scope.exclude_tables):
        return False
    return True
