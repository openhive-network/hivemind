"""HTTP access to the hivemind server under test, addressed as common.yaml addresses it."""

import os
from typing import Any

import requests

_TIMEOUT_SECONDS = 120
# Query parameters PostgREST reserves, by name and by last dot-separated part of the name.
_RESERVED = {"select", "columns", "on_conflict"}
_RESERVED_LAST = {"limit", "offset", "order", "and", "or"}


class ServiceNotConfigured(RuntimeError):
    """An address the checks need is not in the environment."""


def _base_url(address_var: str, port_var: str) -> str:
    address = os.environ.get(address_var)
    port = os.environ.get(port_var)
    if not address or not port:
        raise ServiceNotConfigured(f"{address_var} and {port_var} must name the server to test")
    return f"http://{address}:{port}"


def _is_reserved(name: str) -> bool:
    return name in _RESERVED or name.rpartition(".")[2] in _RESERVED_LAST


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
    """A call of the PostgREST function hivemind_endpoints.`endpoint`, bypassing the rewriter.

    It is made as the rewriter forwards a REST GET: a POST with `params` form-encoded, whose
    fields PostgREST always takes as arguments. In a GET's query string PostgREST would take a
    value starting with a filter operator (`not.`, `eq.`, ...) for a filter. PostgREST's
    reserved parameters among `params` (`limit`, `offset`, ...) go in the query string instead.
    """
    params = params or {}
    reserved = {name: value for name, value in params.items() if _is_reserved(name)}
    return requests.post(
        f"{server_url()}/rpc/{endpoint}",
        params=reserved,
        data={name: value for name, value in params.items() if name not in reserved},
        headers={"accept": "application/json", "content-type": "application/x-www-form-urlencoded"},
        timeout=_TIMEOUT_SECONDS,
    )
