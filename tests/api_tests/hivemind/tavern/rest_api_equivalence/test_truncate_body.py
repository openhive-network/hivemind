"""`truncate-body` of the feed endpoints cuts each post's body and changes nothing else.

For each endpoint the page is requested whole and with `truncate-body`. The truncated page must
hold the same posts in the same order, each equal to its whole form with `body` cut to the first
`truncate-body` characters; `truncate-body=0` must answer byte for byte what no `truncate-body` does.
"""

from typing import Any

import pytest
import requests
from rest_checks import service

# Each endpoint with the arguments of a page in which some body is longer than _TRUNCATE.
_PAGES: dict[str, dict[str, str]] = {
    "get_ranked_posts": {"sort": "trending", "page-size": "20"},
    "get_account_posts": {"account-name": "nkdk", "sort": "blog", "page-size": "20"},
    "search_posts": {"q": "Nyunya", "sort": "created", "page-size": "20"},
}
_TRUNCATE = 100


def _get(endpoint: str, params: dict[str, str]) -> requests.Response:
    if endpoint == "search_posts" and service.search_skip_reason() is not None:
        pytest.skip(service.search_skip_reason())
    response = service.rest_rpc(endpoint, params)
    assert response.status_code == 200, f"HTTP {response.status_code}: {response.text}"
    return response


def _with_body(post: dict[str, Any], body: str) -> dict[str, Any]:
    return {**post, "body": body}


@pytest.mark.parametrize("endpoint", sorted(_PAGES))
def test_truncated_page_is_the_whole_page_with_bodies_cut(endpoint: str) -> None:
    whole = _get(endpoint, _PAGES[endpoint]).json()
    truncated = _get(endpoint, {**_PAGES[endpoint], "truncate-body": str(_TRUNCATE)}).json()

    assert any(len(post["body"]) > _TRUNCATE for post in whole), f"no body of the page is over {_TRUNCATE} characters"
    assert all(len(post["body"]) <= _TRUNCATE for post in truncated)
    assert truncated == [_with_body(post, post["body"][:_TRUNCATE]) for post in whole]


@pytest.mark.parametrize("endpoint", sorted(_PAGES))
def test_zero_truncate_body_is_the_default_response(endpoint: str) -> None:
    default = _get(endpoint, _PAGES[endpoint])
    zero = _get(endpoint, {**_PAGES[endpoint], "truncate-body": "0"})
    assert zero.content == default.content
