"""Configuration: scan scope from the CLI, credentials strictly from env vars."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Optional

ENV_PREFIX = "SNOWFLAKE_"

REQUIRED_ENV = ("SNOWFLAKE_ACCOUNT", "SNOWFLAKE_USER")
# One of these must be present to authenticate.
AUTH_ENV = ("SNOWFLAKE_PASSWORD", "SNOWFLAKE_PRIVATE_KEY_PATH", "SNOWFLAKE_AUTHENTICATOR")
OPTIONAL_ENV = ("SNOWFLAKE_ROLE", "SNOWFLAKE_WAREHOUSE", "SNOWFLAKE_DATABASE")


class ConfigError(Exception):
    pass


@dataclass
class ScanScope:
    """What to scan. Glob patterns are matched case-insensitively."""

    database: str
    schemas: list[str] = field(default_factory=lambda: ["*"])
    tables: list[str] = field(default_factory=lambda: ["*"])
    exclude_tables: list[str] = field(default_factory=list)
    deep: bool = False
    sample_rows: int = 100
    min_confidence: float = 0.4


def connection_params_from_env(environ: Optional[dict] = None) -> dict:
    """Build snowflake.connector.connect() kwargs from SNOWFLAKE_* env vars.

    Raises ConfigError naming the missing variables — never their values.
    """
    env = os.environ if environ is None else environ

    missing = [k for k in REQUIRED_ENV if not env.get(k)]
    if missing:
        raise ConfigError(
            "Missing required environment variable(s): " + ", ".join(missing)
        )
    if not any(env.get(k) for k in AUTH_ENV):
        raise ConfigError(
            "No authentication configured. Set one of: " + ", ".join(AUTH_ENV)
        )

    params: dict = {
        "account": env["SNOWFLAKE_ACCOUNT"],
        "user": env["SNOWFLAKE_USER"],
        # The scanner only reads metadata and aggregate counts.
        "session_parameters": {"QUERY_TAG": "snowflake-pii-scanner"},
    }
    if env.get("SNOWFLAKE_PASSWORD"):
        params["password"] = env["SNOWFLAKE_PASSWORD"]
    if env.get("SNOWFLAKE_AUTHENTICATOR"):
        params["authenticator"] = env["SNOWFLAKE_AUTHENTICATOR"]
    if env.get("SNOWFLAKE_PRIVATE_KEY_PATH"):
        params["private_key"] = _load_private_key(
            env["SNOWFLAKE_PRIVATE_KEY_PATH"],
            env.get("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE"),
        )
    for var, key in (
        ("SNOWFLAKE_ROLE", "role"),
        ("SNOWFLAKE_WAREHOUSE", "warehouse"),
        ("SNOWFLAKE_DATABASE", "database"),
    ):
        if env.get(var):
            params[key] = env[var]
    return params


def _load_private_key(path: str, passphrase: Optional[str]) -> bytes:
    """Load a PKCS#8 private key in the DER form the connector expects."""
    from cryptography.hazmat.primitives import serialization

    with open(path, "rb") as fh:
        key = serialization.load_pem_private_key(
            fh.read(), password=passphrase.encode() if passphrase else None
        )
    return key.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )


def connect(params: dict):
    """Open a Snowflake connection (import is lazy so tests don't need the dep)."""
    import snowflake.connector

    return snowflake.connector.connect(**params)
