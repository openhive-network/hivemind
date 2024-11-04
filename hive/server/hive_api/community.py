"""Hive API: Community methods"""
import logging

from hive.conf import SCHEMA_NAME
from hive.server.common.helpers import json_date, return_error_info, valid_account, valid_community, valid_limit
from hive.server.hive_api.common import get_community_id

# pylint: disable=too-many-lines

log = logging.getLogger(__name__)


@return_error_info
async def get_community(context, name, observer=None):
    """Retrieve full community object. Includes metadata, leadership team

    If `observer` is provided, get subcription status, user title, user role.
    """
    db = context['db']
    name = valid_community(name)
    observer = valid_account(observer, allow_empty=True)

    sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_community( (:name)::VARCHAR, (:observer)::VARCHAR )"
    sql_result = await db.query_row(sql, name=name, observer=observer)
    result = dict(sql_result)

    return result


@return_error_info
async def get_community_context(context, name, account):
    """For a community/account: returns role, title, subscribed state"""
    db = context['db']
    name = valid_community(name)
    account = valid_account(account)

    sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_community_context( (:account)::VARCHAR, (:name)::VARCHAR )"
    row = await db.query_row(sql, account=account, name=name)

    return dict(row['bridge_get_community_context'])


@return_error_info
async def list_top_communities(context, limit=25):
    """List top communities. Returns lite community list."""
    limit = valid_limit(limit, 100, 25)
    sql = f"""SELECT hc.name, hc.title FROM {SCHEMA_NAME}.hive_communities hc
              WHERE hc.rank > 0 ORDER BY hc.rank LIMIT :limit"""
    # ABW: restored older version since hardcoded id is out of the question
    # sql = """SELECT name, title FROM hive_communities
    #          WHERE id = 1344247 OR rank > 0
    #       ORDER BY (CASE WHEN id = 1344247 THEN 0 ELSE rank END)
    #          LIMIT :limit"""

    out = await context['db'].query_all(sql, limit=limit)

    return [(r[0], r[1]) for r in out]


@return_error_info
async def list_pop_communities(context, limit: int = 25):
    """List communities by new subscriber count. Returns lite community list."""
    limit = valid_limit(limit, 25, 25)
    sql = f"SELECT name, title FROM {SCHEMA_NAME}.bridge_list_pop_communities( (:limit)::INT ) ORDER BY newsubs DESC, id DESC"
    out = await context['db'].query_all(sql, limit=limit)

    return [(r[0], r[1]) for r in out]


@return_error_info
async def list_all_subscriptions(context, account):
    """Lists all communities `account` subscribes to, plus role and title in each."""
    db = context['db']
    account = valid_account(account)

    sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_list_all_subscriptions( (:account)::VARCHAR )"
    rows = await db.query_all(sql, account=account)
    return [(r[0], r[1], r[2], r[3]) for r in rows]


@return_error_info
async def list_subscribers(context, community, last='', limit=100):
    """Lists subscribers of `community`."""
    community = valid_community(community)
    last = valid_account(last, True)
    limit = valid_limit(limit, 100, 100)
    db = context['db']
    sql = (
        f"SELECT name, role, title, created_at FROM {SCHEMA_NAME}.bridge_list_subscribers( (:community)::VARCHAR, (:last)::VARCHAR, (:limit)::INT ) ORDER BY name ASC"
    )
    rows = await db.query_all(sql, community=community, last=last, limit=limit)
    return [(r[0], r[1], r[2], json_date(r[3])) for r in rows]


@return_error_info
async def list_communities(context, last='', limit=100, query=None, sort='rank', observer=None):
    """List all communities, paginated. Returns lite community list."""
    # pylint: disable=too-many-arguments, too-many-locals
    last = valid_community(last, True)
    limit = valid_limit(limit, 100, 100)
    supported_sort_list = ['rank', 'new', 'subs']
    assert sort in supported_sort_list, f"Unsupported sort, valid sorts: {', '.join(supported_sort_list)}"
    observer = valid_account(observer, True)
    search = query
    db = context['db']
    order = {"rank": "rank ASC", "new": "id DESC", "subs": "subscribers DESC, id DESC"}
    columns = [
        "id", "name", "title", "about", "lang", "type_id", "is_nsfw",
        "subscribers", "sum_pending", "num_pending", "num_authors",
        "created_at", "avatar_url", "context", "admins"
    ]

    sql = (
            f"SELECT {'(list_communities).*' if sort == 'rank' else ', '.join(columns)} "
            f"FROM {SCHEMA_NAME}.bridge_list_communities_by_{sort}"
            + "( (:observer)::VARCHAR, (:last)::VARCHAR, (:search)::VARCHAR, (:limit)::INT ) "
            f"ORDER BY {order[sort]}"
    )

    rows = await db.query_all(sql, observer=observer, last=last, search=search, limit=limit)

    return remove_empty_admins_field(rows)


@return_error_info
async def list_community_roles(context, community, last='', limit=50):
    """List community account-roles (anyone with non-guest status)."""
    db = context['db']
    community = valid_community(community)
    last = valid_account(last, True)
    limit = valid_limit(limit, 1000, 50)

    sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_list_community_roles( (:community)::VARCHAR, (:last)::VARCHAR, (:limit)::INT )"
    rows = await db.query_all(sql, community=community, last=last, limit=limit)

    return [(r['name'], r['role'], r['title']) for r in rows]


# Communities - internal
# ----------------------
def remove_empty_admins_field(rows):
    result = []
    for r in rows:
        new = dict(r)
        if new['admins'][0] is None:
            del new['admins']
        result.append(new)
    return result


# Stats
# -----


async def top_community_voters(context, community):
    """Get a list of top 5 (pending) community voters."""
    # TODO: which are voting on muted posts?
    db = context['db']
    # TODO: missing validation of community parameter
    top = await _top_community_posts(db, community)
    total = {}
    for _, votes, _ in top:
        for vote in votes.split("\n"):
            voter, rshares = vote.split(',')[:2]
            if voter not in total:
                total[voter] += abs(int(rshares))
    return sorted(total, key=total.get, reverse=True)[:5]


async def top_community_authors(context, community):
    """Get a list of top 5 (pending) community authors."""
    db = context['db']
    # TODO: missing validation of community parameter
    top = await _top_community_posts(db, community)
    total = {}
    for author, _, payout in top:
        if author not in total:
            total[author] = 0
        total[author] += payout
    return sorted(total, key=total.get, reverse=True)[:5]


async def top_community_muted(context, community):
    """Get top authors (by SP) who are muted in a community."""
    db = context['db']
    cid = await get_community_id(db, community)
    sql = f"""SELECT a.name, a.voting_weight, r.title FROM {SCHEMA_NAME}.hive_accounts a
               JOIN {SCHEMA_NAME}.hive_roles r ON a.id = r.account_id
              WHERE r.community_id = :community_id AND r.role_id < 0
           ORDER BY voting_weight DESC LIMIT 5"""
    return await db.query(sql, community_id=cid)


async def _top_community_posts(db, community, limit=50):
    # TODO: muted equivalent
    sql = f"""
    SELECT ha_a.name as author,
        0 as votes,
        ( hp.payout + hp.pending_payout ) as payout
    FROM {SCHEMA_NAME}.hive_posts hp
    INNER JOIN {SCHEMA_NAME}.hive_accounts ha_a ON ha_a.id = hp.author_id
    LEFT JOIN {SCHEMA_NAME}.hive_post_data hpd ON hpd.id = hp.id
    LEFT JOIN {SCHEMA_NAME}.hive_category_data hcd ON hcd.id = hp.category_id
    WHERE hcd.category = :community AND hp.counter_deleted = 0 AND NOT hp.is_paidout
        AND post_id IN (SELECT id FROM {SCHEMA_NAME}.hive_posts WHERE is_muted = '0')
    ORDER BY ( hp.payout + hp.pending_payout ) DESC LIMIT :limit"""

    return await db.query_all(sql, community=community, limit=limit)
