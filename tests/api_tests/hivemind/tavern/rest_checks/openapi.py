"""The OpenAPI document hivemind_endpoints.home() serves, read from the tree's endpoint_schema.sql."""

import json
import os
from typing import Any

_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), *[os.pardir] * 5))
_SCHEMA_SQL = os.path.join(_REPO_ROOT, "hive", "db", "sql_scripts", "endpoints", "endpoint_schema.sql")
_SPEC_START = "openapi json = $$\n"
_SPEC_END = "\n$$;"


def load_spec() -> dict[str, Any]:
    """The OpenAPI document generated into endpoint_schema.sql (scripts/openapi_rewrite.sh)."""
    with open(_SCHEMA_SQL, encoding="utf-8") as handle:
        sql = handle.read()
    start = sql.index(_SPEC_START) + len(_SPEC_START)
    end = sql.index(_SPEC_END, start)
    # The document sits inside the single-quoted EXECUTE FORMAT string, so its quotes are doubled.
    spec: dict[str, Any] = json.loads(sql[start:end].replace("''", "'"))
    return spec


def get_operations(spec: dict[str, Any]) -> dict[str, str]:
    """Each path of `spec` with a GET operation, mapped to that operation's function name."""
    return {path: item["get"]["operationId"] for path, item in spec["paths"].items() if "get" in item}
