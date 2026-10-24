"""Paging property: following a listing's own continuation page by page, with a small page
size, gives the same items, in the same order, as one request with a large page size, as far
as that page reaches, with no item twice."""

from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

from rest_checks import service

# At least this many small pages must be followed for the check to say anything about paging.
MIN_PAGES = 3


class PagingMismatch(Exception):
    """The pages of a listing do not concatenate to its large page."""


@dataclass(frozen=True)
class PagedListing:
    """A list call and how to continue it.

    `fetch(page_size, continuation)` returns one page, `continuation` its argument (None for the
    first page). `next_page(item)` is the continuation for the page after `item`, and `key(item)`
    identifies an item. With `inclusive`, a continued page starts with the item it continues
    from, which is then not counted again.
    """

    fetch: Callable[[int, Any], list[Any]]
    next_page: Callable[[Any], Any]
    key: Callable[[Any], Any]
    small: int
    large: int
    inclusive: bool = False


def rest_listing(
    endpoint: str,
    params: dict[str, str],
    next_page: Callable[[Any], dict[str, str]],
    key: Callable[[Any], Any],
    small: int,
    large: int,
) -> PagedListing:
    """A REST list endpoint paged by `page-size` and the parameters `next_page` gives."""

    def fetch(page_size: int, continuation: dict[str, str] | None) -> list[Any]:
        response = service.rest_rpc(endpoint, {**params, "page-size": str(page_size), **(continuation or {})})
        body = response.json()
        if response.status_code != 200 or not isinstance(body, list):
            raise PagingMismatch(f"{endpoint} answered HTTP {response.status_code}: {body}")
        return body

    return PagedListing(fetch, next_page, key, small, large)


def json_rpc_listing(
    method: str,
    params: dict[str, Any],
    next_page: Callable[[Any], dict[str, Any]],
    key: Callable[[Any], Any],
    small: int,
    large: int,
    inclusive: bool = False,
    items: Callable[[Any], list[Any]] = lambda result: result,
) -> PagedListing:
    """A JSON-RPC list method paged by `limit` and the arguments `next_page` gives;
    `items` extracts the list from the result."""

    def fetch(page_size: int, continuation: dict[str, Any] | None) -> list[Any]:
        response = service.json_rpc(method, {**params, "limit": page_size, **(continuation or {})})
        if "error" in response:
            raise PagingMismatch(f"{method} answered an error: {response['error']}")
        return items(response["result"])

    return PagedListing(fetch, next_page, key, small, large, inclusive)


def _follow(listing: PagedListing, length: int) -> tuple[list[Any], int]:
    items: list[Any] = []
    pages = 0
    continuation = None
    while len(items) < length:
        page = listing.fetch(listing.small, continuation)
        pages += 1
        if continuation is not None and listing.inclusive:
            if not page or listing.key(page[0]) != listing.key(items[-1]):
                raise PagingMismatch(
                    f"page {pages} does not start with {listing.key(items[-1])}, the item it continues from"
                )
            new = page[1:]
        else:
            new = page
        if not new:
            break
        items.extend(new)
        if len(page) < listing.small:
            break
        continuation = listing.next_page(items[-1])
    return items, pages


def check_paging(listing: PagedListing) -> None:
    """Raises PagingMismatch unless the small pages of `listing` concatenate to its large page."""
    large = listing.fetch(listing.large, None)
    if len(large) <= (MIN_PAGES - 1) * listing.small:
        raise PagingMismatch(f"the large page has {len(large)} items, too few for {MIN_PAGES} pages of {listing.small}")
    paged, pages = _follow(listing, len(large))
    if pages < MIN_PAGES:
        raise PagingMismatch(f"only {pages} pages of {listing.small} were followed")
    keys = [listing.key(item) for item in paged]
    repeated = sorted({repr(key) for key in keys if keys.count(key) > 1})
    if repeated:
        raise PagingMismatch(f"items appear on more than one page: {', '.join(repeated[:5])}")
    if len(large) < listing.large and len(paged) != len(large):
        raise PagingMismatch(f"the pages hold {len(paged)} items, the complete large page {len(large)}")
    for index, (item, expected) in enumerate(zip(paged, large, strict=False)):
        if item != expected:
            raise PagingMismatch(
                f"item {index} of the pages is {listing.key(item)}, the large page has {listing.key(expected)} there"
            )
    if len(paged) < len(large):
        raise PagingMismatch(f"the pages end after {len(paged)} items, the large page has {len(large)}")
