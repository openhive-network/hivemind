"""Handles building condenser-compatible response objects."""

import logging
from hive.server.common.helpers import (
    valid_account,
    valid_permlink)
#import ujson as json

from hive.server.bridge_api.methods import get_post
from hive.server.common.helpers import (
    #ApiError,
    return_error_info)

log = logging.getLogger(__name__)

@return_error_info
async def get_post_header(context, author, permlink):
    """Fetch basic post data"""
    db = context['db']
    valid_account(author)
    valid_permlink(permlink)
    sql = """
        SELECT 
            hp.id, ha_a.name as author, hpd_p.permlink as permlink, hcd.category as category, depth
        FROM 
            hive_posts hp
        INNER JOIN hive_accounts ha_a ON ha_a.id = hp.author_id
        INNER JOIN hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id
        LEFT JOIN hive_category_data hcd ON hcd.id = hp.category_id
        WHERE ha_a.name = :author
            AND hpd_p.permlink = :permlink
            AND counter_deleted = 0
    """

    row = await db.query_row(sql, author=author, permlink=permlink)

    assert row, 'Post {}/{} does not exist'.format(author,permlink)

    return dict(
        author=row['author'],
        permlink=row['permlink'],
        category=row['category'],
        depth=row['depth'])


@return_error_info
async def normalize_post(context, post):
    """Takes a steemd post object and outputs bridge-api normalized version."""
    # ABW: at the moment it makes zero sense to have that API method since there is
    # no fat node that would be source of unnormalized posts
    return await get_post(context, post['author'], post['permlink'])

    # decorate
    #if core['community_id']:
    #    sql = """SELECT title FROM hive_communities WHERE id = :id"""
    #    title = await db.query_one(sql, id=core['community_id'])

    #    sql = """SELECT role_id, title
    #               FROM hive_roles
    #              WHERE community_id = :cid
    #                AND account_id = :aid"""
    #    role = await db.query_row(sql, cid=core['community_id'], aid=author['id'])

    #    ret['community_title'] = title
    #    ret['author_role'] = ROLES[role[0] if role else 0]
    #    ret['author_title'] = role[1] if role else ''

    #return ret
