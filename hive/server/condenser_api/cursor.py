"""Cursor-based pagination queries, mostly supporting condenser_api."""

from hive.server.common.helpers import last_month
from json import loads

# pylint: disable=too-many-lines

async def get_post_id(db, author, permlink):
    """Given an author/permlink, retrieve the id from db."""
    sql = """
        SELECT
            hp.id
        FROM hive_posts hp
        INNER JOIN hive_accounts ha_a ON ha_a.id = hp.author_id
        INNER JOIN hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id
        WHERE ha_a.name = :author AND hpd_p.permlink = :permlink
            AND counter_deleted = 0 LIMIT 1""" # ABW: replace with find_comment_id(:author,:permlink,True)?
    return await db.query_one(sql, author=author, permlink=permlink)

async def get_child_ids(db, post_id):
    """Given a parent post id, retrieve all child ids."""
    sql = "SELECT id FROM hive_posts WHERE parent_id = :id AND counter_deleted = 0"
    return await db.query_col(sql, id=post_id)

async def _get_post_id(db, author, permlink):
    """Get post_id from hive db."""
    sql = """
        SELECT
            hp.id
        FROM hive_posts hp
        INNER JOIN hive_accounts ha_a ON ha_a.id = hp.author_id
        INNER JOIN hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id
        WHERE ha_a.name = :author AND hpd_p.permlink = :permlink""" # ABW: what's the difference between that and get_post_id?
    return await db.query_one(sql, author=author, permlink=permlink)

async def _get_account_id(db, name):
    """Get account id from hive db."""
    assert name, 'no account name specified'
    _id = await db.query_one("SELECT id FROM hive_accounts WHERE name = :n", n=name)
    assert _id, "account not found: `%s`" % name
    return _id


async def get_followers(db, account: str, start: str, follow_type: str, limit: int):
    """Get a list of accounts following a given account."""
    account_id = await _get_account_id(db, account)
    start_id = await _get_account_id(db, start) if start else None
    state = 2 if follow_type == 'ignore' else 1

    seek = ''
    if start_id:
        seek = """AND hf.created_at <= (
                     SELECT created_at FROM hive_follows
                      WHERE following = :account_id
                        AND follower = :start_id)"""

    sql = """
        SELECT name FROM hive_follows hf
     LEFT JOIN hive_accounts ha ON hf.follower = ha.id
         WHERE hf.following = :account_id
           AND state = :state %s
      ORDER BY hf.created_at DESC
         LIMIT :limit
    """ % seek

    return await db.query_col(sql, account_id=account_id, start_id=start_id,
                              state=state, limit=limit)


async def get_following(db, account: str, start: str, follow_type: str, limit: int):
    """Get a list of accounts followed by a given account."""
    account_id = await _get_account_id(db, account)
    start_id = await _get_account_id(db, start) if start else None
    state = 2 if follow_type == 'ignore' else 1

    seek = ''
    if start_id:
        seek = """AND hf.created_at <= (
                     SELECT created_at FROM hive_follows
                      WHERE follower = :account_id
                        AND following = :start_id)"""

    sql = """
        SELECT name FROM hive_follows hf
     LEFT JOIN hive_accounts ha ON hf.following = ha.id
         WHERE hf.follower = :account_id
           AND state = :state %s
      ORDER BY hf.created_at DESC
         LIMIT :limit
    """ % seek

    return await db.query_col(sql, account_id=account_id, start_id=start_id,
                              state=state, limit=limit)


async def get_follow_counts(db, account: str):
    """Return following/followers count for `account`."""
    account_id = await _get_account_id(db, account)
    sql = """SELECT following, followers
               FROM hive_accounts
              WHERE id = :account_id"""
    return dict(await db.query_row(sql, account_id=account_id))


async def get_reblogged_by(db, author: str, permlink: str):
    """Return all rebloggers of a post."""
    post_id = await _get_post_id(db, author, permlink)
    assert post_id, "post not found"
    sql = """SELECT name FROM hive_accounts
               JOIN hive_feed_cache ON id = account_id
              WHERE post_id = :post_id"""
    names = await db.query_col(sql, post_id=post_id)
    if author in names:
        names.remove(author)
    return names

async def pids_by_blog(db, account: str, start_author: str = '',
                       start_permlink: str = '', limit: int = 20):
    """Get a list of post_ids for an author's blog."""
    account_id = await _get_account_id(db, account)

    seek = ''
    start_id = None
    if start_permlink:
        start_id = await _get_post_id(db, start_author, start_permlink)
        if not start_id:
            return []

        seek = """
          AND created_at <= (
            SELECT created_at
              FROM hive_feed_cache
             WHERE account_id = :account_id
               AND post_id = :start_id)
        """

    sql = """
        SELECT post_id
          FROM hive_feed_cache
         WHERE account_id = :account_id %s
      ORDER BY created_at DESC
         LIMIT :limit
    """ % seek

    return await db.query_col(sql, account_id=account_id, start_id=start_id, limit=limit)


async def pids_by_blog_without_reblog(db, account: str, start_permlink: str = '', limit: int = 20):
    """Get a list of post_ids for an author's blog without reblogs."""

    is_start_id = False
    start_id = 0
    if start_permlink:
        start_id = await _get_post_id(db, account, start_permlink)
        if not start_id:
            return []
        is_start_id = True

    sql = "SELECT id FROM get_pids_by_blog_without_reblog( '{}', {}, {}, {} )".format( account, start_id, is_start_id, limit )

    return await db.query_col(sql)


async def pids_by_feed_with_reblog(db, account: str, start_author: str = '',
                                   start_permlink: str = '', limit: int = 20):
    """Get a list of [post_id, reblogged_by_str] for an account's feed."""
    account_id = await _get_account_id(db, account)

    seek = ''
    start_id = None
    if start_permlink:
        start_id = await _get_post_id(db, start_author, start_permlink)
        if not start_id:
            return []

        seek = """
          HAVING MIN(hive_feed_cache.created_at) <= (
            SELECT MIN(created_at) FROM hive_feed_cache WHERE post_id = :start_id
               AND account_id IN (SELECT following FROM hive_follows
                                  WHERE follower = :account AND state = 1))
        """

    sql = """
        SELECT post_id, string_agg(name, ',') accounts
          FROM hive_feed_cache
          JOIN hive_follows ON account_id = hive_follows.following AND state = 1
          JOIN hive_accounts ON hive_follows.following = hive_accounts.id
         WHERE hive_follows.follower = :account
           AND hive_feed_cache.created_at > :cutoff
      GROUP BY post_id %s
      ORDER BY MIN(hive_feed_cache.created_at) DESC LIMIT :limit
    """ % seek

    result = await db.query_all(sql, account=account_id, start_id=start_id,
                                limit=limit, cutoff=last_month())
    return [(row[0], row[1]) for row in result]


async def pids_by_account_comments(db, account: str, start_permlink: str = '', limit: int = 20):
    """Get a list of post_ids representing comments by an author."""
    is_start_id = False
    start_id = 0
    if start_permlink:
        start_id = await _get_post_id(db, account, start_permlink)
        if not start_id:
            return []
        is_start_id = True

    # `depth` in ORDER BY is a no-op, but forces an ix3 index scan (see #189)
    sql = "SELECT id FROM get_pids_by_account_comments( '{}', {}, {}, {} )".format( account, start_id, is_start_id, limit )
    return await db.query_col(sql)


async def pids_by_replies_to_account(db, start_author: str, start_permlink: str = '',
                                     limit: int = 20):
    """Get a list of post_ids representing replies to an author.

    To get the first page of results, specify `start_author` as the
    account being replied to. For successive pages, provide the
    last loaded reply's author/permlink.
    """
    start_id = 0
    is_start_id = False
    if start_permlink:
        sql = """
          SELECT (SELECT name FROM hive_accounts WHERE id = parent.author_id),
                 child.id
            FROM hive_posts child
            JOIN hive_posts parent
              ON child.parent_id = parent.id
           WHERE child.author_id = (SELECT id FROM hive_accounts WHERE name = :author)
             AND child.permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :permlink)
        """

        row = await db.query_row(sql, author=start_author, permlink=start_permlink)
        if not row:
            return []

        is_start_id = True
        parent_account = row[0]
        start_id = row[1]
    else:
        parent_account = start_author

    sql = " SELECT id FROM get_pids_by_replies_to_account( '{}', {}, {}, {} ) ".format( parent_account, start_id, is_start_id, limit )

    return await db.query_col(sql)
