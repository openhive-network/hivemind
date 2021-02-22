"""Hive API: Stats"""
import logging

from hive.server.common.helpers import return_error_info, valid_limit

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
        SELECT hc.name, hc.title, author, payout, posts, authors
          FROM payout_stats_view
     LEFT JOIN hive_communities hc ON hc.id = community_id
         WHERE (community_id IS NULL AND author IS NOT NULL)
            OR (community_id IS NOT NULL AND author IS NULL)
      ORDER BY payout DESC
         LIMIT :limit
    """

    rows = await db.query_all(sql, limit=limit)
    items = list(map(_row, rows))

    sql = """SELECT SUM(payout) FROM payout_stats_view WHERE author IS NULL"""
    total = await db.query_one(sql)

    sql = """SELECT SUM(payout) FROM payout_stats_view
              WHERE community_id IS NULL AND author IS NULL"""
    blog_ttl = await db.query_one(sql)

    return dict(items=items, total=float(total if total is not None else 0.), blogs=float(blog_ttl if blog_ttl is not None else 0.))
