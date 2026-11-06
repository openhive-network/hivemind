"""`votes` of the post list endpoints: `full` is the default page, `none` and `summary` drop `active_votes`.

For each endpoint one page is requested with each `votes`. `votes=full` must answer byte for byte
what no `votes` does. With `votes=none` the page must hold the same posts in the same order, each
equal to its full form without `active_votes` and with `observer_vote` null (there is no observer).
With `votes=summary` each post is its `none` form plus `top_votes`: the _TOP_VOTES votes of its full
`active_votes` with the largest absolute rshares, ties by voter account id, the order of `active_votes`.
"""

from typing import Any

import pytest
import requests
from rest_checks import service

# Each endpoint with the arguments of a page whose posts all have more than _TOP_VOTES votes and
# fewer than the 1000 `active_votes` holds at most, so `top_votes` can be derived from it.
_PAGES: dict[str, dict[str, str]] = {
    "get_ranked_posts": {"sort": "trending", "page-size": "20"},
    "get_account_posts": {"account-name": "blocktrades", "sort": "blog", "page-size": "20"},
}
_TOP_VOTES = 10
_ACTIVE_VOTES_LIMIT = 1000


def _get(endpoint: str, params: dict[str, str]) -> requests.Response:
    response: requests.Response = service.rest_rpc(endpoint, params)
    assert response.status_code == 200, f"HTTP {response.status_code}: {response.text}"
    return response


def _vote_free(post: dict[str, Any]) -> dict[str, Any]:
    return {**{key: value for key, value in post.items() if key != "active_votes"}, "observer_vote": None}


def _top_votes(active_votes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_size = sorted(active_votes, key=lambda vote: -abs(int(vote["rshares"])))
    return [{"voter": vote["voter"], "rshares": vote["rshares"]} for vote in by_size[:_TOP_VOTES]]


def _full_page(endpoint: str) -> list[dict[str, Any]]:
    page: list[dict[str, Any]] = _get(endpoint, _PAGES[endpoint]).json()
    assert page, "the page is empty"
    for post in page:
        assert _TOP_VOTES < len(post["active_votes"]) < _ACTIVE_VOTES_LIMIT, f"{post['author']}/{post['permlink']}"
    return page


@pytest.mark.parametrize("endpoint", sorted(_PAGES))
def test_full_votes_is_the_default_response(endpoint: str) -> None:
    default = _get(endpoint, _PAGES[endpoint])
    full = _get(endpoint, {**_PAGES[endpoint], "votes": "full"})
    assert full.content == default.content


@pytest.mark.parametrize("endpoint", sorted(_PAGES))
def test_no_votes_page_is_the_full_page_without_active_votes(endpoint: str) -> None:
    full = _full_page(endpoint)
    none = _get(endpoint, {**_PAGES[endpoint], "votes": "none"}).json()
    assert none == [_vote_free(post) for post in full]


@pytest.mark.parametrize("endpoint", sorted(_PAGES))
def test_summary_page_holds_the_largest_votes(endpoint: str) -> None:
    full = _full_page(endpoint)
    summary = _get(endpoint, {**_PAGES[endpoint], "votes": "summary"}).json()

    assert [{key: value for key, value in post.items() if key != "top_votes"} for post in summary] == [
        _vote_free(post) for post in full
    ]
    for summarised, whole in zip(summary, full, strict=True):
        top = summarised["top_votes"]
        assert len(top) == _TOP_VOTES
        assert [{"voter": vote["voter"], "rshares": vote["rshares"]} for vote in top] == _top_votes(
            whole["active_votes"]
        )
