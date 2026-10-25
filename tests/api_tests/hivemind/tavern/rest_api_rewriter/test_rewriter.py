"""Every path of the OpenAPI document, requested at its public URL through the postgrest-rewriter.

A request reaches its own endpoint when:
- an extra, unknown query parameter makes PostgREST name the function the request was
  routed to (PGRST202), which must be the path's operationId, with the path's parameters;
- the answer equals that of the function called directly, with the path parameters as
  query parameters.
"""

from urllib.parse import quote

import pytest
from rest_checks import openapi, service

_SPEC = openapi.load_spec()
_OPERATIONS = openapi.get_operations(_SPEC)
_PUBLIC_PREFIX = _SPEC["servers"][0]["url"]
_PROBE = "rewriter-probe"

_POST = {"author": "xeroc", "permlink": "piston-web-first-open-source-steem-gui---searching-for-alpha-testers"}
_DISCUSSED_POST = {"author": "test-safari", "permlink": "please-comment-hive2-03"}

# For each path: values of its path parameters and the query of a request answered with 200.
_REQUESTS: dict[str, tuple[dict[str, str], dict[str, str]]] = {
    "/accounts/{account-name}/operations": ({"account-name": "blocktrades"}, {"page-size": "5"}),
    "/accounts/{account-name}/pending-author-rewards": ({"account-name": "guest4test1"}, {}),
    "/accounts/{account-name}/pending-curation-rewards": ({"account-name": "geekgirl"}, {}),
    "/accounts/{account-name}/relationships": ({"account-name": "flw1"}, {"accounts": "flw2,flw3"}),
    "/accounts/{account-name}/votes": ({"account-name": "gtg"}, {"page-size": "3"}),
    "/accounts/{account-name}/posts": ({"account-name": "gtg"}, {"sort": "comments", "page-size": "3"}),
    "/accounts/{account-name}/profile": ({"account-name": "alice"}, {}),
    "/accounts/{account-name}/followers": ({"account-name": "gtg"}, {"page-size": "3"}),
    "/accounts/{account-name}/following": ({"account-name": "gtg"}, {"page-size": "3"}),
    "/accounts/{account-name}/notifications": ({"account-name": "gtg"}, {"min-score": "0", "page-size": "3"}),
    "/accounts/{account-name}/notifications/unread": ({"account-name": "gtg"}, {"min-score": "0"}),
    "/accounts/{account-name}/follow-lists/{type}": ({"account-name": "followtest", "type": "follow_muted"}, {}),
    "/accounts/{account-name}/follows-any-lists": ({"account-name": "alice"}, {}),
    "/accounts/{account-name}/subscriptions": ({"account-name": "gtg"}, {}),
    "/blog/reblogs": ({}, {"sort": "trending", "tag": "", "observer": "gtg", "page-size": "3"}),
    "/blog/votes": ({}, {"sort": "trending", "tag": "", "observer": "gtg", "page-size": "3"}),
    "/posts": ({}, {"sort": "created", "tag": "all", "page-size": "3"}),
    "/posts/{author}/{permlink}": (_DISCUSSED_POST, {}),
    "/posts/{author}/{permlink}/replies": (_DISCUSSED_POST, {}),
    "/posts/{author}/{permlink}/votes": (_POST, {"page-size": "3"}),
    "/posts/{author}/{permlink}/discussion": (_DISCUSSED_POST, {}),
    "/posts/{author}/{permlink}/header": (_POST, {}),
    "/posts/{author}/{permlink}/reblogged-by": ({"author": "skypilot", "permlink": "melting-rock"}, {}),
    "/communities": ({}, {"page-size": "3"}),
    "/communities/{name}": ({"name": "hive-117600"}, {}),
    "/communities/{name}/subscribers": ({"name": "hive-165317"}, {"page-size": "3"}),
    "/communities/{name}/roles": ({"name": "hive-171744"}, {"page-size": "3"}),
    "/search/posts": ({}, {"q": "hive", "sort": "created", "page-size": "3"}),
    "/tags/trending": ({}, {"page-size": "3"}),
    "/sync-status": ({}, {}),
    "/version": ({}, {}),
}


def _public_url(path: str, path_params: dict[str, str]) -> str:
    for name, value in path_params.items():
        path = path.replace("{" + name + "}", quote(value, safe=""))
    return f"{service.rewriter_url()}{_PUBLIC_PREFIX}{path}"


def test_every_path_of_the_spec_is_requested() -> None:
    assert set(_REQUESTS) == set(_OPERATIONS)


@pytest.mark.parametrize("path", sorted(_OPERATIONS))
def test_path_reaches_its_endpoint(path: str) -> None:
    if path.startswith("/search/") and service.search_skip_reason() is not None:
        pytest.skip(service.search_skip_reason())
    function = _OPERATIONS[path]
    path_params, query = _REQUESTS[path]
    url = _public_url(path, path_params)

    probe = service.rest_get(url, {**query, _PROBE: "1"}).json()
    routed_args = sorted([*path_params, *query, _PROBE])
    assert probe.get("code") == "PGRST202", f"{url} did not reach a PostgREST function: {probe}"
    assert probe["message"] == f"Could not find the function {function}({', '.join(routed_args)}) in the schema cache"

    routed = service.rest_get(url, query)
    direct = service.rest_rpc(function.split(".", 1)[1], {**path_params, **query})
    assert direct.status_code == 200, f"{function} answered HTTP {direct.status_code}: {direct.text}"
    assert routed.status_code == 200, f"{url} answered HTTP {routed.status_code}: {routed.text}"
    assert routed.json() == direct.json()
