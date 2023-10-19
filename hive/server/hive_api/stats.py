"""Hive API: Stats"""
import logging

from hive.conf import SCHEMA_NAME
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

    sql = f"""
        SELECT hc.name, hc.title, author, payout, posts, authors
          FROM {SCHEMA_NAME}.payout_stats_view
     LEFT JOIN {SCHEMA_NAME}.hive_communities hc ON hc.id = community_id
         WHERE (community_id IS NULL AND author IS NOT NULL)
            OR (community_id IS NOT NULL AND author IS NULL)
      ORDER BY payout DESC
         LIMIT :limit
    """

    rows = await db.query_all(sql, limit=limit)
    items = list(map(_row, rows))

    sql = f"""SELECT SUM(payout) FROM {SCHEMA_NAME}.payout_stats_view WHERE author IS NULL"""
    total = await db.query_one(sql)

    sql = f"""SELECT SUM(payout) FROM {SCHEMA_NAME}.payout_stats_view
              WHERE community_id IS NULL AND author IS NULL"""
    blog_ttl = await db.query_one(sql)

    return dict(
        items=items,
        total=float(total if total is not None else 0.0),
        blogs=float(blog_ttl if blog_ttl is not None else 0.0),
    )
