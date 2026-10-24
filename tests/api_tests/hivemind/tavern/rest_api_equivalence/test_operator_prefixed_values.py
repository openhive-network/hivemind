"""REST arguments whose value starts with a PostgREST filter operator reach the function verbatim.

In a GET's query string PostgREST takes such a value (`not.existing`, `eq.gtg`) for a filter on
the result, so the argument would never reach the function. Each case sets one text parameter
of an endpoint to such a value and requests it both directly, as the rewriter forwards a GET,
and at its public URL through the rewriter. The answer must equal the answer of the JSON-RPC
method the endpoint wraps to the same call.
"""

import re
from typing import Any
from urllib.parse import quote

import pytest
import requests
from rest_checks import openapi, service
from rest_checks.equivalence import MAPPINGS, EndpointMapping

_PREFIXES = ("not.", "eq.", "in.", "like.", "is.", "fts.")
_SUFFIX = "existing"
_POST = {"author": "test-safari", "permlink": "please-comment-hive2-03"}

# For each REST parameter: the endpoint it is tried on, the JSON-RPC argument it carries and
# the other JSON-RPC arguments of the call.
_TARGETS: dict[str, tuple[str, str, dict[str, Any]]] = {
    "account-name": ("get_account_profile", "account", {}),
    "author": ("get_post", "author", {"permlink": _POST["permlink"]}),
    "start-author": ("get_ranked_posts", "start_author", {"sort": "created", "start_permlink": _POST["permlink"]}),
    "observer": ("get_account_profile", "observer", {"account": "alice"}),
    "tag": ("get_ranked_posts", "tag", {"sort": "trending"}),
    "q": ("search_posts", "pattern", {"sort": "created"}),
    "last": ("get_communities", "last", {}),
    "start": ("get_account_followers", "start", {"account": "gtg"}),
    "community": ("get_account_notifications", "community", {"account": "gtg"}),
}

_BY_ENDPOINT = {mapping.endpoint: mapping for mapping in MAPPINGS}
_SPEC = openapi.load_spec()
_PUBLIC_PREFIX = _SPEC["servers"][0]["url"]
_PUBLIC_PATHS = {function.split(".", 1)[1]: path for path, function in openapi.get_operations(_SPEC).items()}
_PATH_PARAM = re.compile(r"\{([^}]+)\}")


def _public_get(endpoint: str, params: dict[str, str]) -> requests.Response:
    path = _PUBLIC_PATHS[endpoint]
    path_params = _PATH_PARAM.findall(path)
    for name in path_params:
        path = path.replace("{" + name + "}", quote(params[name], safe=""))
    query = {name: value for name, value in params.items() if name not in path_params}
    return service.rest_get(f"{service.rewriter_url()}{_PUBLIC_PREFIX}{path}", query)


def _direct(endpoint: str, params: dict[str, str]) -> requests.Response:
    return service.rest_rpc(endpoint, params)


_TRANSPORTS = {"direct": _direct, "rewriter": _public_get}


def _assert_same_answer(mapping: EndpointMapping, rest: requests.Response, rpc: dict[str, Any]) -> None:
    body = rest.json()
    if "error" in rpc:
        error = rpc["error"]
        data = error.get("data")
        expected = {"message": error.get("message"), "details": data if isinstance(data, str) else None}
        assert rest.status_code == 400, f"HTTP {rest.status_code}, the JSON-RPC error {expected} was expected: {body}"
        assert {"message": body.get("message"), "details": body.get("details")} == expected
        return
    result = rpc["result"]
    if result is None and mapping.rows:
        result = []
    assert rest.status_code == 200, f"HTTP {rest.status_code}, a result was expected: {body}"
    assert body == result


@pytest.mark.parametrize("transport", sorted(_TRANSPORTS))
@pytest.mark.parametrize("prefix", _PREFIXES)
@pytest.mark.parametrize("rest_param", sorted(_TARGETS))
def test_operator_prefixed_value_reaches_the_function(rest_param: str, prefix: str, transport: str) -> None:
    endpoint, arg, other_args = _TARGETS[rest_param]
    mapping = _BY_ENDPOINT[endpoint]
    if mapping.method.startswith("search-api.") and service.search_skip_reason() is not None:
        pytest.skip(service.search_skip_reason())
    args = {**other_args, arg: prefix + _SUFFIX}
    rest_params = {mapping.params[name][0]: value for name, value in args.items()}

    rpc = service.json_rpc(mapping.method, args)
    rest = _TRANSPORTS[transport](endpoint, rest_params)
    _assert_same_answer(mapping, rest, rpc)


def test_dotted_name_profile_matches_bridge_get_profile() -> None:
    # `all.` is no PostgREST operator, so this name is an argument even in a GET's query string.
    name = "all.about.sports"
    mapping = _BY_ENDPOINT["get_account_profile"]
    rpc = service.json_rpc(mapping.method, {"account": name})
    for rest in (
        _public_get(mapping.endpoint, {"account-name": name}),
        service.rest_get(f"{service.server_url()}/rpc/{mapping.endpoint}", {"account-name": name}),
        _direct(mapping.endpoint, {"account-name": name}),
    ):
        _assert_same_answer(mapping, rest, rpc)
