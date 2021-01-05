"""Hive API: Public endpoints"""

import logging

from hive.server.hive_api.objects import accounts_by_name, posts_by_id
from hive.server.hive_api.common import (
    get_account_id, split_url,
    valid_account, valid_permlink, valid_limit)
from hive.server.condenser_api.cursor import get_followers, get_following

from hive.db.schema import DB_VERSION as SCHEMA_DB_VERSION

log = logging.getLogger(__name__)

# Accounts

async def get_account(context, name, observer):
    """Get a full account object by `name`.

    Observer: will include `followed`/`muted` context.
    """
    assert name, 'name cannot be blank'
    return await accounts_by_name(context['db'], [valid_account(name)], observer, lite=False)

async def get_accounts(context, names, observer=None):
    """Find and return lite accounts by `names`.

    Observer: will include `followed` context.
    """
    assert isinstance(names, list), 'names must be a list'
    assert names, 'names cannot be blank'
    assert len(names) < 100, 'too many accounts requested'
    return await accounts_by_name(context['db'], names, observer, lite=True)


# Follows/mute

async def list_followers(context, account:str, start:str='', limit:int=50, observer:str=None):
    """Get a list of all accounts following `account`."""
    followers = await get_followers(
        context['db'],
        valid_account(account),
        valid_account(start, allow_empty=True),
        1, # blog
        valid_limit(limit, 100, 50))
    return await accounts_by_name(context['db'], followers, observer, lite=True)

async def list_following(context, account:str, start:str='', limit:int=50, observer:str=None):
    """Get a list of all accounts `account` follows."""
    following = await get_following(
        context['db'],
        valid_account(account),
        valid_account(start, allow_empty=True),
        1, # blog
        valid_limit(limit, 100, 50))
    return await accounts_by_name(context['db'], following, observer, lite=True)

async def list_all_muted(context, account):
    """Get a list of all account names muted by `account`."""
    db = context['db']
    account = valid_account(account)
    sql = """SELECT a.name FROM hive_follows f
               JOIN hive_accounts a ON f.following_id = a.id
              WHERE follower = :follower AND state = 2"""
    return await db.query_col(sql, follower=get_account_id(db, account))

async def get_info(context):
    db = context['db']

    sql = "SELECT num FROM hive_blocks ORDER BY num DESC LIMIT 1"
    database_head_block = await db.query_one(sql)

    from hive.version import VERSION, GIT_REVISION

    ret = {
        "hivemind_version" : VERSION,
        "hivemind_git_rev" : GIT_REVISION,
        "database_schema_version" : SCHEMA_DB_VERSION,
        "database_head_block" : database_head_block
    }

    return ret
