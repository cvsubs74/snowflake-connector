import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))


class FakeCursor:
    """Routes queries to canned results: INFORMATION_SCHEMA queries return
    `catalog_rows`; per-table deep-scan queries return `table_rows[table]`."""

    def __init__(self, catalog_rows=(), table_rows=None):
        self.catalog_rows = list(catalog_rows)
        self.table_rows = table_rows or {}
        self.queries = []
        self._current = None

    def execute(self, query):
        self.queries.append(query)
        if "INFORMATION_SCHEMA.COLUMNS" in query:
            self._current = self.catalog_rows
        else:
            table = next(
                (t for t in self.table_rows if f'"{t}"' in query), None
            )
            if table is None:
                raise AssertionError(f"unexpected query: {query}")
            self._current = [self.table_rows[table]]

    def fetchall(self):
        return self._current

    def fetchone(self):
        return self._current[0]
