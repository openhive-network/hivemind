"""condenser_api trending tag fetching methods"""

from aiocache import cached
from hive.server.common.helpers import (return_error_info, valid_tag, valid_limit)

@return_error_info
@cached(ttl=7200, timeout=1200)
async def get_top_trending_tags_summary(context):
    """Get top 50 trending tags among pending posts."""
    sql = "SELECT condenser_get_top_trending_tags_summary(50)"
    return await context['db'].query_col(sql)

@return_error_info
@cached(ttl=3600, timeout=1200)
async def get_trending_tags(context, start_tag: str = '', limit: int = 250):
    """Get top 250 trending tags among pending posts, with stats."""

    limit = valid_limit(limit, 250, 250)
    start_tag = valid_tag(start_tag, allow_empty=True)

    sql = "SELECT * FROM condenser_get_trending_tags( (:tag)::VARCHAR, :limit )"

    out = []
    for row in await context['db'].query_all(sql, limit=limit, tag=start_tag):
        out.append({
            'name': row['category'],
            'comments': row['total_posts'] - row['top_posts'],
            'top_posts': row['top_posts'],
            'total_payouts': "%.3f HBD" % row['total_payouts']})

    return out
