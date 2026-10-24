"""PostgREST's reserved query parameters keep their PostgREST meaning through the rewriter.

The rewriter forwards a GET of a function as a form-encoded POST, whose fields PostgREST takes as
arguments. `limit` and `offset` must stay in the query string, where they trim the rows the
function returns, while the other parameters, operator-prefixed values included, still reach the
function as arguments.
"""

from typing import Any

import requests
from rest_checks import openapi, service

_SPEC = openapi.load_spec()
_PUBLIC_PREFIX = _SPEC["servers"][0]["url"]
_PAGE_SIZE = "5"


def _public_get(path: str, params: dict[str, str]) -> requests.Response:
    return service.rest_get(f"{service.rewriter_url()}{_PUBLIC_PREFIX}{path}", params)


def _rows(response: requests.Response) -> list[Any]:
    assert response.status_code == 200, f"{response.url} answered HTTP {response.status_code}: {response.text}"
    rows = response.json()
    assert isinstance(rows, list), f"{response.url} answered no rows: {rows}"
    return rows


def _trending_page() -> list[Any]:
    page = _rows(_public_get("/tags/trending", {"page-size": _PAGE_SIZE}))
    assert len(page) >= 3, f"too few trending tags to trim: {page}"
    return page


def test_limit_trims_the_rows() -> None:
    page = _trending_page()
    assert _rows(_public_get("/tags/trending", {"page-size": _PAGE_SIZE, "limit": "2"})) == page[:2]


def test_offset_and_limit_select_rows_of_the_page() -> None:
    page = _trending_page()
    assert _rows(_public_get("/tags/trending", {"page-size": _PAGE_SIZE, "offset": "1", "limit": "2"})) == page[1:3]


def test_operator_prefixed_argument_reaches_the_function_beside_limit() -> None:
    # The observer of trending topics is only checked to be a well-formed account name.
    observer = "not.existing"
    rpc = service.json_rpc("bridge.get_trending_topics", {"limit": int(_PAGE_SIZE), "observer": observer})
    assert len(rpc["result"]) >= 2, f"too few trending topics to trim: {rpc}"
    rows = _rows(_public_get("/tags/trending", {"page-size": _PAGE_SIZE, "observer": observer, "limit": "1"}))
    assert rows == rpc["result"][:1]


def test_operator_prefixed_path_argument_beside_limit_is_answered_as_upstream() -> None:
    routed = _public_get("/accounts/not.existing/followers", {"limit": "1"})
    direct = service.rest_rpc("get_account_followers", {"account-name": "not.existing", "limit": "1"})
    assert (routed.status_code, routed.json()) == (direct.status_code, direct.json()), routed.text
