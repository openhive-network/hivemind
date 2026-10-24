"""Paging property of every paged REST endpoint and JSON-RPC method, on the fixture's data.

Each listing's arguments select enough rows for at least rest_checks.paging.MIN_PAGES pages.
"""

from typing import Any

import pytest
from rest_checks import service
from rest_checks.paging import PagedListing, check_paging, json_rpc_listing, rest_listing

# A post with more than 1000 votes and a thread with more than 20 replies in the 5M-block fixture.
_VOTED_POST = ("xeroc", "piston-web-first-open-source-steem-gui---searching-for-alpha-testers")
_DISCUSSED_POST = ("dollarvigilante", "steemit-is-a-scam-how-bernie-sanders-screwed-me")
_POST_PAGE = 5
_POSTS_PER_CALL = 20


def _post_key(post: dict[str, Any]) -> tuple[str, str]:
    return post["author"], post["permlink"]


def _rest_after_post(post: dict[str, Any]) -> dict[str, str]:
    return {"start-author": post["author"], "start-permlink": post["permlink"]}


def _json_rpc_after_post(post: dict[str, Any]) -> dict[str, str]:
    return {"start_author": post["author"], "start_permlink": post["permlink"]}


def _rest_posts(endpoint: str, params: dict[str, str]) -> PagedListing:
    return rest_listing(endpoint, params, _rest_after_post, _post_key, _POST_PAGE, _POSTS_PER_CALL)


def _json_rpc_posts(method: str, params: dict[str, str]) -> PagedListing:
    return json_rpc_listing(method, params, _json_rpc_after_post, _post_key, _POST_PAGE, _POSTS_PER_CALL)


def _vote_key(vote: dict[str, Any]) -> tuple[str, str, str]:
    return vote["voter"], vote["author"], vote["permlink"]


def _first_item(row: list[Any]) -> Any:
    return row[0]


_LISTINGS = {
    "rest get_ranked_posts": _rest_posts("get_ranked_posts", {"sort": "trending", "tag": ""}),
    "json-rpc bridge.get_ranked_posts": _json_rpc_posts("bridge.get_ranked_posts", {"sort": "trending", "tag": ""}),
    "rest get_account_posts": _rest_posts("get_account_posts", {"account-name": "gtg", "sort": "comments"}),
    "json-rpc bridge.get_account_posts": _json_rpc_posts(
        "bridge.get_account_posts", {"account": "gtg", "sort": "comments"}
    ),
    "rest get_post_replies": _rest_posts(
        "get_post_replies", {"author": _DISCUSSED_POST[0], "permlink": _DISCUSSED_POST[1]}
    ),
    "rest get_votes": _rest_posts("get_votes", {"sort": "trending", "tag": "", "observer": "gtg"}),
    "rest get_reblogs": _rest_posts("get_reblogs", {"sort": "trending", "tag": "", "observer": "gtg"}),
    "rest get_post_votes": rest_listing(
        "get_post_votes",
        {"author": _VOTED_POST[0], "permlink": _VOTED_POST[1]},
        lambda vote: {"start-voter": vote["voter"]},
        lambda vote: vote["voter"],
        100,
        1000,
    ),
    "rest get_account_votes": rest_listing(
        "get_account_votes", {"account-name": "gtg"}, _rest_after_post, _post_key, 100, 1000
    ),
    "json-rpc database_api.list_votes by_comment_voter": json_rpc_listing(
        "database_api.list_votes",
        {"order": "by_comment_voter", "start": [_VOTED_POST[0], _VOTED_POST[1], ""]},
        lambda vote: {"start": [vote["author"], vote["permlink"], vote["voter"]]},
        _vote_key,
        100,
        1000,
        inclusive=True,
        items=lambda result: result["votes"],
    ),
    "json-rpc database_api.list_votes by_voter_comment": json_rpc_listing(
        "database_api.list_votes",
        {"order": "by_voter_comment", "start": ["gtg", "", ""]},
        lambda vote: {"start": [vote["voter"], vote["author"], vote["permlink"]]},
        _vote_key,
        100,
        1000,
        inclusive=True,
        items=lambda result: result["votes"],
    ),
    "rest get_account_followers": rest_listing(
        "get_account_followers",
        {"account-name": "gtg"},
        lambda follow: {"start": follow["follower"]},
        lambda follow: follow["follower"],
        20,
        1000,
    ),
    "json-rpc condenser_api.get_followers": json_rpc_listing(
        "condenser_api.get_followers",
        {"account": "gtg", "follow_type": "blog"},
        lambda follow: {"start": follow["follower"]},
        lambda follow: follow["follower"],
        20,
        1000,
    ),
    "rest get_account_following": rest_listing(
        "get_account_following",
        {"account-name": "gtg"},
        lambda follow: {"start": follow["following"]},
        lambda follow: follow["following"],
        10,
        1000,
    ),
    "json-rpc condenser_api.get_following": json_rpc_listing(
        "condenser_api.get_following",
        {"account": "gtg", "follow_type": "blog"},
        lambda follow: {"start": follow["following"]},
        lambda follow: follow["following"],
        10,
        1000,
    ),
    "rest get_account_notifications": rest_listing(
        "get_account_notifications",
        {"account-name": "gtg", "min-score": "0"},
        lambda notification: {"last-id": str(notification["id"])},
        lambda notification: notification["id"],
        25,
        100,
    ),
    "json-rpc bridge.account_notifications": json_rpc_listing(
        "bridge.account_notifications",
        {"account": "gtg", "min_score": 0},
        lambda notification: {"last_id": int(notification["id"])},
        lambda notification: notification["id"],
        25,
        100,
    ),
    "rest get_communities": rest_listing(
        "get_communities",
        {"sort": "rank"},
        lambda community: {"last": community["name"]},
        lambda community: community["name"],
        4,
        100,
    ),
    "json-rpc bridge.list_communities": json_rpc_listing(
        "bridge.list_communities",
        {"sort": "rank"},
        lambda community: {"last": community["name"]},
        lambda community: community["name"],
        4,
        100,
    ),
    "rest get_community_subscribers": rest_listing(
        "get_community_subscribers",
        {"name": "hive-165317"},
        lambda subscriber: {"last": subscriber[0]},
        _first_item,
        2,
        100,
    ),
    "json-rpc bridge.list_subscribers": json_rpc_listing(
        "bridge.list_subscribers",
        {"community": "hive-165317"},
        lambda subscriber: {"last": subscriber[0]},
        _first_item,
        2,
        100,
    ),
    "rest get_community_roles": rest_listing(
        "get_community_roles",
        {"name": "hive-171744"},
        lambda role: {"last": role[0]},
        _first_item,
        25,
        1000,
    ),
    "json-rpc bridge.list_community_roles": json_rpc_listing(
        "bridge.list_community_roles",
        {"community": "hive-171744"},
        lambda role: {"last": role[0]},
        _first_item,
        25,
        1000,
    ),
}


_SEARCH_LISTINGS = {
    "rest search_posts relevance": _rest_posts("search_posts", {"q": "hive", "sort": "relevance"}),
    "rest search_posts created": _rest_posts("search_posts", {"q": "hive", "sort": "created"}),
    "json-rpc search-api.find_text relevance": _json_rpc_posts(
        "search-api.find_text", {"pattern": "hive", "sort": "relevance"}
    ),
    "json-rpc search-api.find_text created": _json_rpc_posts(
        "search-api.find_text", {"pattern": "hive", "sort": "created"}
    ),
}


@pytest.mark.parametrize("name", sorted(_LISTINGS))
def test_pages_concatenate_to_the_large_page(name: str) -> None:
    check_paging(_LISTINGS[name])


@pytest.mark.parametrize("name", sorted(_SEARCH_LISTINGS))
def test_search_pages_concatenate_to_the_large_page(name: str) -> None:
    reason = service.search_skip_reason()
    if reason is not None:
        pytest.skip(reason)
    check_paging(_SEARCH_LISTINGS[name])
