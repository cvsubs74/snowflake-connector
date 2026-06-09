import pytest

from snowflake_pii_scanner.config import ConfigError, connection_params_from_env

BASE_ENV = {
    "SNOWFLAKE_ACCOUNT": "xy12345.us-east-1",
    "SNOWFLAKE_USER": "scanner",
    "SNOWFLAKE_PASSWORD": "s3cret",
}


def test_password_auth_params():
    params = connection_params_from_env(dict(BASE_ENV))
    assert params["account"] == "xy12345.us-east-1"
    assert params["user"] == "scanner"
    assert params["password"] == "s3cret"
    assert params["session_parameters"]["QUERY_TAG"] == "snowflake-pii-scanner"


def test_optional_params_passed_through():
    env = dict(BASE_ENV, SNOWFLAKE_ROLE="READONLY", SNOWFLAKE_WAREHOUSE="WH",
               SNOWFLAKE_DATABASE="ANALYTICS")
    params = connection_params_from_env(env)
    assert params["role"] == "READONLY"
    assert params["warehouse"] == "WH"
    assert params["database"] == "ANALYTICS"


def test_missing_required_vars_named_without_values():
    with pytest.raises(ConfigError) as exc:
        connection_params_from_env({"SNOWFLAKE_USER": "scanner"})
    assert "SNOWFLAKE_ACCOUNT" in str(exc.value)
    assert "scanner" not in str(exc.value)


def test_missing_auth_rejected():
    env = {"SNOWFLAKE_ACCOUNT": "a", "SNOWFLAKE_USER": "u"}
    with pytest.raises(ConfigError) as exc:
        connection_params_from_env(env)
    assert "SNOWFLAKE_PASSWORD" in str(exc.value)


def test_authenticator_auth_accepted():
    env = {"SNOWFLAKE_ACCOUNT": "a", "SNOWFLAKE_USER": "u",
           "SNOWFLAKE_AUTHENTICATOR": "externalbrowser"}
    params = connection_params_from_env(env)
    assert params["authenticator"] == "externalbrowser"
    assert "password" not in params
