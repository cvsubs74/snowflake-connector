from snowflake_pii_scanner.cli import build_parser, main


def test_parser_scope_flags():
    args = build_parser().parse_args([
        "--database", "ANALYTICS",
        "--schemas", "PUBLIC,SALES",
        "--exclude-tables", "TMP_*,*_STAGING",
        "--deep", "--sample-rows", "200", "--min-confidence", "0.6",
        "--format", "csv", "--output", "out.csv",
    ])
    assert args.database == "ANALYTICS"
    assert args.schemas == ["PUBLIC", "SALES"]
    assert args.exclude_tables == ["TMP_*", "*_STAGING"]
    assert args.deep and args.sample_rows == 200
    assert args.min_confidence == 0.6
    assert args.format == "csv" and args.output == "out.csv"


def test_main_fails_cleanly_without_credentials(monkeypatch, capsys):
    for var in ("SNOWFLAKE_ACCOUNT", "SNOWFLAKE_USER", "SNOWFLAKE_PASSWORD",
                "SNOWFLAKE_PRIVATE_KEY_PATH", "SNOWFLAKE_AUTHENTICATOR"):
        monkeypatch.delenv(var, raising=False)
    rc = main(["--database", "ANALYTICS"])
    assert rc == 2
    err = capsys.readouterr().err
    assert "SNOWFLAKE_ACCOUNT" in err


def test_main_end_to_end_with_fake_connection(monkeypatch, tmp_path, capsys):
    from conftest import FakeCursor

    cursor = FakeCursor(catalog_rows=[("PUBLIC", "CUSTOMERS", "EMAIL", "TEXT")])

    class FakeConn:
        def cursor(self):
            return cursor

        def close(self):
            pass

    cursor.close = lambda: None
    monkeypatch.setenv("SNOWFLAKE_ACCOUNT", "acct")
    monkeypatch.setenv("SNOWFLAKE_USER", "user")
    monkeypatch.setenv("SNOWFLAKE_PASSWORD", "pw")
    monkeypatch.setattr("snowflake_pii_scanner.cli.connect", lambda params: FakeConn())

    out_file = tmp_path / "report.json"
    rc = main(["--database", "ANALYTICS", "--output", str(out_file)])
    assert rc == 0
    assert "PUBLIC.CUSTOMERS.EMAIL" in capsys.readouterr().out
    assert out_file.exists()
    assert '"category": "EMAIL"' in out_file.read_text()
