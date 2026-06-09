# snowflake-pii-scanner

A Python CLI that connects to Snowflake and automatically identifies which columns are likely to contain PII (Personally Identifiable Information), across 13 categories.

**Raw data never leaves Snowflake.** Pattern matching is pushed into the database; only aggregate match counts are returned.

---

## PII categories detected

Email · Phone · National ID (SSN, Aadhaar, …) · Credit card · Person name · Address · Date of birth · IP address · Passport · Driver's license · Bank account / IBAN · Gender · Geolocation

---

## How detection works

Detection runs in two tiers:

| Tier | Trigger | What leaves Snowflake |
|---|---|---|
| **Metadata** | always | Column names + types from `INFORMATION_SCHEMA` |
| **Deep** | `--deep` flag | Aggregate match counts only |

**Metadata tier:** column names are matched case-insensitively against per-category rules. Zero table data egress.

**Deep tier:** one aggregate query per table runs `REGEXP_LIKE` over a `SAMPLE (N ROWS)` and returns `COUNT_IF(...)` totals. Values are matched *inside* Snowflake — they are structurally prevented from being transferred, logged, or written to any report.

**Confidence scoring:** a column-name match contributes 0.6; an in-database value-match ratio *r* adds 0.4 × *r* (or scores 0.8 × *r* alone for value-only discoveries, reported only when ≥ 30% of sampled values match).

---

## Setup

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"          # installs snowflake-connector-python + pytest
```

---

## Credentials

Credentials come **only** from environment variables — never from CLI flags. Missing-variable errors name the variable without echoing values. Sessions are tagged `QUERY_TAG=snowflake-pii-scanner` for auditability.

| Variable | Required | Notes |
|---|---|---|
| `SNOWFLAKE_ACCOUNT` | ✅ | e.g. `xy12345.us-east-1` |
| `SNOWFLAKE_USER` | ✅ | |
| `SNOWFLAKE_PASSWORD` | one of these three | password auth |
| `SNOWFLAKE_PRIVATE_KEY_PATH` | one of these three | key-pair auth (PEM, PKCS#8); add `SNOWFLAKE_PRIVATE_KEY_PASSPHRASE` if encrypted |
| `SNOWFLAKE_AUTHENTICATOR` | one of these three | e.g. `externalbrowser` for SSO |
| `SNOWFLAKE_ROLE` | optional | recommended: a read-only role |
| `SNOWFLAKE_WAREHOUSE` | optional | |

---

## Usage

```bash
# Metadata-only scan — no table data leaves Snowflake
snowflake-pii-scan --database ANALYTICS

# Deep scan of two schemas, excluding staging tables, JSON output
snowflake-pii-scan --database ANALYTICS \
    --schemas PUBLIC,SALES \
    --exclude-tables 'TMP_*,*_STAGING' \
    --deep --sample-rows 200 \
    --output pii-report.json

# CSV export with a higher confidence floor
snowflake-pii-scan --database ANALYTICS --deep \
    --min-confidence 0.6 --format csv --output pii-report.csv
```

`python -m snowflake_pii_scanner ...` works identically.

### All flags

| Flag | Default | Description |
|---|---|---|
| `--database` | required | Database to scan |
| `--schemas GLOB[,…]` | `*` | Schema name globs to include |
| `--tables GLOB[,…]` | `*` | Table name globs to include |
| `--exclude-tables GLOB[,…]` | none | Table name globs to exclude |
| `--deep` | off | Enable in-database value profiling |
| `--sample-rows N` | 100 | Rows sampled per table for `--deep` |
| `--min-confidence 0–1` | 0.4 | Confidence floor for reported findings |
| `--format json\|csv` | json | Report format for `--output` |
| `--output PATH` | none | Write full report to file (console summary always printed) |
| `-v / --verbose` | off | Debug logging |

### Example console output

```
Snowflake PII scan — database ANALYTICS
  columns flagged: 4  (across 2 tables)

COLUMN                                CATEGORY      CONF  EVIDENCE
PUBLIC.CUSTOMERS.EMAIL                EMAIL         0.96  name+values
PUBLIC.CUSTOMERS.PHONE_NUMBER         PHONE         0.60  name
PUBLIC.ORDERS.BILLING_ADDRESS         ADDRESS       0.60  name
PUBLIC.USERS.CONTACT_INFO             EMAIL         0.72  values
```

### Example JSON report (excerpt)

```json
{
  "scanner_version": "0.1.0",
  "scope": { "database": "ANALYTICS", "deep": true, "sample_rows": 100 },
  "summary": { "columns_flagged": 4, "tables_flagged": 2 },
  "findings": [
    {
      "database": "ANALYTICS", "schema": "PUBLIC",
      "table": "CUSTOMERS", "column": "EMAIL", "data_type": "TEXT",
      "categories": [
        {
          "category": "EMAIL", "confidence": 0.96,
          "name_matched": true,
          "value_match_ratio": 0.9, "sampled_rows": 100
        }
      ]
    }
  ]
}
```

Reports contain identifiers, categories, and aggregate statistics only — never sampled values.

---

## Tests

```bash
python -m pytest
```

65 tests covering rules, config validation, scope filtering, deep-scan SQL generation, confidence math, and report serialization. No Snowflake account or network access required — the connector is imported lazily and tests use fake cursors.

---

## Caveats

- **Checksum validation is out of scope.** Regex matching can't validate Luhn (credit cards) or IBAN check digits, so numeric ID columns can produce false positives under `--deep`. Use the confidence floor and evidence-type field to triage.
- **Embedded PII in free-text columns is not detected.** The tool scans column-level granularity; values inside JSON blobs or prose strings are outside scope.
- **SAMPLE is non-deterministic.** Results may differ across runs for the same table. Increase `--sample-rows` for more stable ratios.

---

## License

MIT
