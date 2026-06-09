"""Snowflake PII scanner — find columns likely to contain personal data.

Detection happens in two tiers:

* metadata tier — column names from INFORMATION_SCHEMA are matched against
  per-category rules; no table data leaves Snowflake.
* deep tier (opt-in) — value patterns are evaluated *inside* Snowflake via
  REGEXP_LIKE over a row sample; only aggregate match counts are returned,
  so raw values are never transferred, logged, or persisted.
"""

__version__ = "0.1.0"
