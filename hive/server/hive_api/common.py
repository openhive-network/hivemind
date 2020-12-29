"""Hive API: Internal supporting methods"""
import logging

from hive.server.common.helpers import (
    valid_account,
    valid_permlink,
    valid_limit)

log = logging.getLogger(__name__)

def __used_refs():
    # pylint
    valid_limit('')

async def get_community_id(db, name):
    """Get community id from db."""
    assert name, 'community name cannot be blank'
    return await db.query_one("SELECT find_community_id( (:name)::VARCHAR, True )", name=name)

async def get_account_id(db, name):
    """Get account id from account name."""
    return await db.query_one("SELECT find_account_id( (:name)::VARCHAR, True )", name=name)

def estimated_sp(vests):
    """Convert VESTS to SP units for display."""
    return vests * 0.0005034

VALID_COMMENT_SORTS = [
    'hot'  # hot algo
    'top', # payout
    'new', # newest
    #'votes', # highest number of votes (excludes comm. muted?)
]
def valid_comment_sort(sort):
    """Validate and return provided `sort`, otherwise throw."""
    assert isinstance(sort, str), 'sort was not a string'
    assert sort in VALID_COMMENT_SORTS, 'invalid sort `%s`' % sort
    return sort

def split_url(url, allow_empty=False):
    """Validate and split a post url into author/permlink."""
    if not url:
        assert allow_empty, 'url must be specified'
        return None
    assert isinstance(url, str), 'url must be a string'

    parts = url.split('/')
    assert len(parts) == 2, 'invalid url parts'

    author = valid_account(parts[0])
    permlink = valid_permlink(parts[1])
    return (author, permlink)
