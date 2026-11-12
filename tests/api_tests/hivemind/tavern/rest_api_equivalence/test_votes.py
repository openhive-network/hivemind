"""`votes` of the endpoints returning bridge posts: `full` is the default, `none` and `summary` drop `active_votes`.

For each endpoint one response is requested with each `votes`. `votes=full` must answer byte for byte
what no `votes` does. With `votes=none` the response must hold the same posts in the same order (a
discussion: under the same keys), each equal to its full form without `active_votes` and with
`observer_vote` null (there is no observer). With `votes=summary` each post is its `none` form plus
`top_votes`: the _TOP_VOTES votes of its full `active_votes` with the largest absolute rshares, ties by
voter account id, the order of `active_votes`.
"""

from collections.abc import Callable
from typing import Any

import pytest
import requests
from rest_checks import service

_Post = dict[str, Any]

# A thread of 663 posts, the largest in the fixture.
_THREAD = {"author": "rolypoli20", "permlink": "poli-s-grand-kpop-album-giveaway-promo"}

# Each endpoint with the arguments of a response whose posts all have fewer than the 1000 votes
# `active_votes` holds at most, so `top_votes` can be derived from it, and some more than _TOP_VOTES.
# The shape says how the response holds its posts: a list, one post, or a discussion keyed by
# `author/permlink`.
_CASES: dict[str, tuple[dict[str, str], str]] = {
    "get_ranked_posts": ({"sort": "trending", "page-size": "20"}, "list"),
    "get_account_posts": ({"account-name": "blocktrades", "sort": "blog", "page-size": "20"}, "list"),
    "get_post": ({"author": "gtg", "permlink": "heavy-duty-witness-node-infrastructure"}, "post"),
    "get_post_discussion": (_THREAD, "discussion"),
    "get_post_replies": ({**_THREAD, "page-size": "20"}, "list"),
    "search_posts": ({"q": "hive", "sort": "relevance", "page-size": "20"}, "list"),
    "search_similar_posts": (
        {"author": "xeroc", "permlink": "piston-web-first-open-source-steem-gui---searching-for-alpha-testers"},
        "list",
    ),
}
_TOP_VOTES = 10
_ACTIVE_VOTES_LIMIT = 1000
_REPLIES_PAGE = 5


def _get(endpoint: str, params: dict[str, str]) -> requests.Response:
    response: requests.Response = service.rest_rpc(endpoint, params)
    assert response.status_code == 200, f"HTTP {response.status_code}: {response.text}"
    return response


def _map_posts(body: Any, shape: str, change: Callable[[_Post], Any]) -> Any:
    if shape == "post":
        return change(body)
    if shape == "discussion":
        return {key: change(post) for key, post in body.items()}
    return [change(post) for post in body]


def _posts(body: Any, shape: str) -> list[_Post]:
    if shape == "post":
        return [body]
    if shape == "discussion":
        return list(body.values())
    return list(body)


def _vote_free(post: _Post) -> _Post:
    return {**{key: value for key, value in post.items() if key != "active_votes"}, "observer_vote": None}


def _without_top_votes(post: _Post) -> _Post:
    return {key: value for key, value in post.items() if key != "top_votes"}


def _vote_list(votes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [{"voter": vote["voter"], "rshares": vote["rshares"]} for vote in votes]


def _top_votes(active_votes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return _vote_list(sorted(active_votes, key=lambda vote: -abs(int(vote["rshares"])))[:_TOP_VOTES])


def _full(endpoint: str) -> Any:
    params, shape = _CASES[endpoint]
    body = _get(endpoint, params).json()
    posts = _posts(body, shape)
    assert posts, "the response holds no post"
    for post in posts:
        assert len(post["active_votes"]) < _ACTIVE_VOTES_LIMIT, f"{post['author']}/{post['permlink']}"
    assert any(len(post["active_votes"]) > _TOP_VOTES for post in posts), "no post has more votes than top_votes"
    return body


@pytest.mark.parametrize("endpoint", sorted(_CASES))
def test_full_votes_is_the_default_response(endpoint: str) -> None:
    params, _shape = _CASES[endpoint]
    default = _get(endpoint, params)
    full = _get(endpoint, {**params, "votes": "full"})
    assert full.content == default.content


@pytest.mark.parametrize("endpoint", sorted(_CASES))
def test_no_votes_is_the_full_response_without_active_votes(endpoint: str) -> None:
    params, shape = _CASES[endpoint]
    full = _full(endpoint)
    none = _get(endpoint, {**params, "votes": "none"}).json()
    assert none == _map_posts(full, shape, _vote_free)


@pytest.mark.parametrize("endpoint", sorted(_CASES))
def test_summary_holds_the_largest_votes(endpoint: str) -> None:
    params, shape = _CASES[endpoint]
    full = _full(endpoint)
    summary = _get(endpoint, {**params, "votes": "summary"}).json()

    assert _map_posts(summary, shape, _without_top_votes) == _map_posts(full, shape, _vote_free)
    assert _map_posts(summary, shape, lambda post: _vote_list(post["top_votes"])) == _map_posts(
        full, shape, lambda post: _top_votes(post["active_votes"])
    )


@pytest.mark.parametrize("votes", ["summary", "none"])
def test_replies_page_the_same_with_every_votes(votes: str) -> None:
    params, _shape = _CASES["get_post_replies"]
    first = {**params, "page-size": str(_REPLIES_PAGE)}
    full_first = _get("get_post_replies", first).json()
    assert len(full_first) == _REPLIES_PAGE
    second = {**first, "start-author": full_first[-1]["author"], "start-permlink": full_first[-1]["permlink"]}
    full_second = _get("get_post_replies", second).json()
    assert full_second, "the thread has no second page of replies"

    for page, full_page in ((first, full_first), (second, full_second)):
        replies = _get("get_post_replies", {**page, "votes": votes}).json()
        assert [_without_top_votes(reply) for reply in replies] == [_vote_free(reply) for reply in full_page]
