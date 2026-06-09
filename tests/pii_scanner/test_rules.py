import re

import pytest

from snowflake_pii_scanner.rules import RULES, match_column_name, rule_for


@pytest.mark.parametrize("column,expected", [
    ("email", "EMAIL"),
    ("CUSTOMER_EMAIL", "EMAIL"),
    ("e_mail_addr", "EMAIL"),
    ("phone_number", "PHONE"),
    ("mobile", "PHONE"),
    ("ssn", "NATIONAL_ID"),
    ("social_security_no", "NATIONAL_ID"),
    ("tax_id", "NATIONAL_ID"),
    ("credit_card_number", "CREDIT_CARD"),
    ("cc_num", "CREDIT_CARD"),
    ("first_name", "PERSON_NAME"),
    ("surname", "PERSON_NAME"),
    ("FULLNAME", "PERSON_NAME"),
    ("street_address", "ADDRESS"),
    ("zip_code", "ADDRESS"),
    ("date_of_birth", "DATE_OF_BIRTH"),
    ("dob", "DATE_OF_BIRTH"),
    ("ip_address", "IP_ADDRESS"),
    ("client_ip", "IP_ADDRESS"),
    ("passport_no", "PASSPORT"),
    ("drivers_license_number", "DRIVERS_LICENSE"),
    ("iban", "BANK_ACCOUNT"),
    ("account_number", "BANK_ACCOUNT"),
    ("gender", "GENDER"),
    ("latitude", "GEOLOCATION"),
])
def test_name_match_positive(column, expected):
    assert expected in {r.category for r in match_column_name(column)}


@pytest.mark.parametrize("column", [
    "id", "created_at", "order_total", "status", "description",
    "company", "session_token", "quantity", "tincture",  # 'tin' bounded
    "expanded",  # 'pan' bounded
])
def test_name_match_negative(column):
    assert match_column_name(column) == []


VALUE_CASES = {
    "EMAIL": (["alice@example.com", "b.smith+tag@sub.domain.co.uk"],
              ["not-an-email", "a@b", "@example.com"]),
    "PHONE": (["+1 (415) 555-0123", "415-555-0123", "4155550123"],
              ["12", "phone", ""]),
    "NATIONAL_ID": (["123-45-6789"], ["123456789", "12-345-6789"]),
    "CREDIT_CARD": (["4111111111111111", "5500005555555559", "378282246310005"],
                    ["1234567890123456", "411111111111111x"]),
    "IP_ADDRESS": (["192.168.0.1", "10.0.0.255"], ["192.168.0", "a.b.c.d"]),
    "BANK_ACCOUNT": (["GB82WEST12345698765432", "DE89370400440532013000"],
                     ["1234567890", "gb82west12345698765432"]),
}


@pytest.mark.parametrize("category", sorted(VALUE_CASES))
def test_value_patterns(category):
    pattern = rule_for(category).value_pattern
    positives, negatives = VALUE_CASES[category]
    for value in positives:
        assert re.fullmatch(pattern, value), f"{category} should match {value!r}"
    for value in negatives:
        assert not re.fullmatch(pattern, value), f"{category} should not match {value!r}"


def test_patterns_are_dollar_quote_safe():
    # Deep-scan SQL embeds patterns as $$...$$ literals.
    for rule in RULES:
        if rule.value_pattern:
            assert "$$" not in rule.value_pattern
