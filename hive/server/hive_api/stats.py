"""Hive API: Stats"""
import logging

from hive.server.common.helpers import return_error_info
from hive.server.common.payout_stats import PayoutStats
from hive.server.hive_api.common import valid_limit

log = logging.getLogger(__name__)

def _row(row):
    if row['name']:
        url = row['name']
        label = row['title']
    else:
        url = '@' + row['author']
        label = url

    return (url, label, float(row['payout']), row['posts'], row['authors'])

@return_error_info
async def get_payout_stats(context, limit=250):
    """Get payout stats for building treemap."""
    db = context['db']
    limit = valid_limit(limit, 250, 250)

    sql = """
          SELECT hc.name, hc.title, author, payout, posts, NULL authors
          FROM
          (
            SELECT community_id, ha.name as author, SUM( payout + pending_payout ) payout, COUNT(*) posts, NULL authors
            FROM hive_posts
            INNER JOIN hive_accounts ha ON ha.id = hive_posts.author_id
            WHERE is_paidout = '0' and counter_deleted = 0
            GROUP BY community_id, author

            UNION ALL

            SELECT community_id, NULL author, SUM( payout + pending_payout ) payout, COUNT(*) posts, COUNT(DISTINCT(author_id)) authors
            FROM hive_posts
            WHERE is_paidout = '0' and counter_deleted = 0
            GROUP BY community_id
          ) T
          LEFT JOIN hive_communities hc ON hc.id = T.community_id
          WHERE (T.community_id IS NULL AND T.author IS NOT NULL) OR (T.community_id IS NOT NULL AND T.author IS NULL)
          ORDER BY payout DESC
          LIMIT :limit
    """

    rows = await db.query_all(sql, limit=limit)
    items = list(map(_row, rows))

    sql = """
          SELECT SUM( payout + pending_payout ) payout
          FROM hive_posts
          WHERE is_paidout = '0' and counter_deleted = 0
          """
    total = await db.query_one(sql)

    sql = """
          SELECT SUM( payout + pending_payout ) payout
          FROM hive_posts
          WHERE is_paidout = '0' and counter_deleted = 0 and community_id IS NULL
          """
    blog_ttl = await db.query_one(sql)

    return dict(items=items, total=float(total if total is not None else 0.), blogs=float(blog_ttl if blog_ttl is not None else 0.))
