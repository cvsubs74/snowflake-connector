# Snowflake PII Scanner

A Python CLI that connects to Snowflake and identifies which columns likely
contain PII (emails, phone numbers, national IDs, credit cards, names,
addresses, dates of birth, IPs, passports, driver's licenses, bank accounts,
gender, geolocation).

## Design

Detection runs in two tiers:

| Tier | Trigger | What leaves Snowflake |
|---|---|---|
| Metadata | always | Column names + types from `INFORMATION_SCHEMA` |
| Deep | `--deep` flag | Aggregate match **counts** only |

The deep tier pushes value profiling *into* Snowflake: one query per table
runs `REGEXP_LIKE` over a `SAMPLE (N ROWS)` and returns
`COUNT_IF(...)` aggregates. Raw column values are never transferred, logged,
or written to disk — by construction, not by policy.

Each finding gets a confidence score (0–1): a column-name match contributes
0.6; an in-database value-match ratio `r` adds `0.4 × r` (or scores `0.8 × r`
alone when only values match, reported only when `r ≥ 0.3`).

Known caveats: pattern-based detection cannot validate checksums (e.g. Luhn
for card numbers), so numeric ID columns can false-positive under `--deep`;
free-text columns holding embedded PII are out of scope.

## Setup

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"          # installs snowflake-connector-python + pytest
```

## Credentials (environment variables only)

| Variable | Required | Notes |
|---|---|---|
| `SNOWFLAKE_ACCOUNT` | ✅ | e.g. `xy12345.us-east-1` |
| `SNOWFLAKE_USER` | ✅ | |
| `SNOWFLAKE_PASSWORD` | one of these three | password auth |
| `SNOWFLAKE_PRIVATE_KEY_PATH` | one of these three | key-pair auth (PEM, PKCS#8); optional `SNOWFLAKE_PRIVATE_KEY_PASSPHRASE` |
| `SNOWFLAKE_AUTHENTICATOR` | one of these three | e.g. `externalbrowser` for SSO |
| `SNOWFLAKE_ROLE` / `SNOWFLAKE_WAREHOUSE` | optional | use a read-only role |

Secrets are never accepted as CLI flags, never logged, and missing-variable
errors name the variable only. Sessions are tagged
`QUERY_TAG=snowflake-pii-scanner` for auditability.

## Usage

```bash
# Metadata-only scan of one database (no table data leaves Snowflake)
snowflake-pii-scan --database ANALYTICS

# Deep scan of two schemas, excluding temp tables, exporting JSON
snowflake-pii-scan --database ANALYTICS \
    --schemas PUBLIC,SALES --exclude-tables 'TMP_*,*_STAGING' \
    --deep --sample-rows 200 \
    --output pii-report.json

# CSV export, higher confidence floor
snowflake-pii-scan --database ANALYTICS --deep \
    --min-confidence 0.6 --format csv --output pii-report.csv
```

`python -m snowflake_pii_scanner ...` works identically.

The console always prints a summary table; `--output` additionally writes the
full report (scan scope, summary, per-column categories with confidence,
evidence type, match ratios) as JSON or CSV.

## Tests

```bash
python -m pytest
```

The suite uses fake cursors — no Snowflake account or network access is
required, and `snowflake-connector-python` itself is imported lazily so tests
run without it installed.
