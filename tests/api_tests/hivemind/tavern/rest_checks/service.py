"""HTTP access to the hivemind server under test, addressed as common.yaml addresses it."""

import os
from typing import Any

import requests

_TIMEOUT_SECONDS = 120


class ServiceNotConfigured(RuntimeError):
    """An address the checks need is not in the environment."""


def _base_url(address_var: str, port_var: str) -> str:
    address = os.environ.get(address_var)
    port = os.environ.get(port_var)
    if not address or not port:
        raise ServiceNotConfigured(f"{address_var} and {port_var} must name the server to test")
    return f"http://{address}:{port}"


def server_url() -> str:
    """PostgREST serving the JSON-RPC root and /rpc/<endpoint> (HIVEMIND_ADDRESS, HIVEMIND_PORT)."""
    return _base_url("HIVEMIND_ADDRESS", "HIVEMIND_PORT")


def rewriter_url() -> str:
    """The postgrest-rewriter in front of that PostgREST (HIVEMIND_REWRITER_ADDRESS, HIVEMIND_REWRITER_PORT)."""
    return _base_url("HIVEMIND_REWRITER_ADDRESS", "HIVEMIND_REWRITER_PORT")


def search_skip_reason() -> str | None:
    """Why search-api cannot be tested on this server (HIVEMIND_SKIP_SEARCH), or None when it can."""
    return os.environ.get("HIVEMIND_SKIP_SEARCH") or None


def json_rpc(method: str, params: Any) -> Any:
    """The JSON-RPC response object for `method` called with `params`."""
    body = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
    response = requests.post(f"{server_url()}/", json=body, timeout=_TIMEOUT_SECONDS)
    response.raise_for_status()
    return response.json()


def rest_get(url: str, params: dict[str, str] | None = None) -> requests.Response:
    """A GET of `url` as a REST client makes it."""
    return requests.get(url, params=params, headers={"accept": "application/json"}, timeout=_TIMEOUT_SECONDS)


def rest_rpc(endpoint: str, params: dict[str, str] | None = None) -> requests.Response:
    """A GET of the PostgREST function hivemind_endpoints.`endpoint`, bypassing the rewriter."""
    return rest_get(f"{server_url()}/rpc/{endpoint}", params)
