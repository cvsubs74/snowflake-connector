"""PII detection rules.

Each rule describes one PII category:

* ``name_pattern`` — case-insensitive regex matched against column names.
* ``value_pattern`` — regex matched against column *values*. Written to be
  valid both for Python ``re`` (used in tests) and Snowflake ``REGEXP_LIKE``
  (which implicitly anchors to the whole subject — the explicit ``^...$``
  anchors keep the two engines in agreement).
* ``value_only`` — if True, the value pattern is precise enough to test
  against every text-like column during a deep scan, not just columns whose
  name already matched.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class PIIRule:
    category: str
    name_pattern: str
    value_pattern: Optional[str] = None
    value_only: bool = False


RULES: tuple[PIIRule, ...] = (
    PIIRule(
        category="EMAIL",
        name_pattern=r"(^|[_-])e?mail",
        value_pattern=r"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$",
        value_only=True,
    ),
    PIIRule(
        category="PHONE",
        name_pattern=r"phone|mobile|cell(_|$)|fax|msisdn",
        value_pattern=r"^\+?[-. ()]*([0-9][-. ()]*){7,15}$",
    ),
    PIIRule(
        category="NATIONAL_ID",
        name_pattern=r"(^|[_-])ssn|social_?sec|national_?id|aadhaar|nino|tax_?id|(^|[_-])tin($|[_-])",
        value_pattern=r"^[0-9]{3}-[0-9]{2}-[0-9]{4}$",
        value_only=True,
    ),
    PIIRule(
        category="CREDIT_CARD",
        name_pattern=r"credit_?card|card_?(num|no)|cc_?num|(^|[_-])pan($|[_-])",
        value_pattern=(
            r"^(4[0-9]{12}([0-9]{3})?"
            r"|5[1-5][0-9]{14}"
            r"|3[47][0-9]{13}"
            r"|6(011|5[0-9]{2})[0-9]{12})$"
        ),
        value_only=True,
    ),
    PIIRule(
        category="PERSON_NAME",
        name_pattern=r"(first|last|middle|full|given|family|maiden)_?name|surname|fullname",
    ),
    PIIRule(
        category="ADDRESS",
        name_pattern=r"address|(^|[_-])street|zip_?code|postal|postcode",
    ),
    PIIRule(
        category="DATE_OF_BIRTH",
        name_pattern=r"birth|(^|[_-])dob($|[_-])",
    ),
    PIIRule(
        category="IP_ADDRESS",
        name_pattern=r"(^|[_-])ip_?(addr|address)?($|[_-])",
        value_pattern=r"^([0-9]{1,3}\.){3}[0-9]{1,3}$",
        value_only=True,
    ),
    PIIRule(
        category="PASSPORT",
        name_pattern=r"passport",
    ),
    PIIRule(
        category="DRIVERS_LICENSE",
        name_pattern=r"(driver|driving).{0,3}licen[cs]e|(^|[_-])dl_?(num|no)",
    ),
    PIIRule(
        category="BANK_ACCOUNT",
        name_pattern=r"iban|bank_?acc|account_?(num|no)|routing_?(num|no)|swift|(^|[_-])bic($|[_-])",
        value_pattern=r"^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$",
    ),
    PIIRule(
        category="GENDER",
        name_pattern=r"gender|(^|[_-])sex($|[_-])",
    ),
    PIIRule(
        category="GEOLOCATION",
        name_pattern=r"latitude|longitude|(^|[_-])lat_?l(on|ng)|geolocation|geo_?coord",
    ),
)

# Data types whose values REGEXP_LIKE can sensibly profile once cast to text.
TEXTUAL_TYPES = frozenset(
    {"TEXT", "VARCHAR", "CHAR", "CHARACTER", "STRING", "NUMBER", "INT", "INTEGER",
     "BIGINT", "SMALLINT", "TINYINT", "DECIMAL", "NUMERIC"}
)


def match_column_name(column_name: str) -> list[PIIRule]:
    """Return every rule whose name pattern matches the column name."""
    name = column_name.strip().lower()
    return [r for r in RULES if re.search(r.name_pattern, name, re.IGNORECASE)]


def value_only_rules() -> list[PIIRule]:
    return [r for r in RULES if r.value_only and r.value_pattern]


def rule_for(category: str) -> PIIRule:
    for r in RULES:
        if r.category == category:
            return r
    raise KeyError(category)
