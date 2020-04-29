# pylint: disable=too-many-arguments,line-too-long,too-many-lines
from hive.server.common.helpers import return_error_info, valid_limit
from hive.server.common.objects import condenser_post_object

async def get_post_id_by_author_and_permlink(db, author: str, permlink: str, limit: int):
    """Return post ids for given author and permlink"""
    sql = """SELECT post_id FROM hive_posts_cache WHERE author >= :author AND permlink >= :permlink ORDER BY author ASC, permlink ASC, post_id ASC LIMIT :limit"""
    result = await db.query_row(sql, author=author, permlink=permlink, limit=limit)
    return result.post_id

@return_error_info
async def list_comments(context, start: list, limit: int, order: str):
    """Returns all comments, starting with the specified options."""
    print("Hivemind native list_comments")
    supported_order_list = ['by_cashout_time', 'by_permlink', 'by_root', 'by_parent', 'by_update', 'by_author_last_update']
    assert order in supported_order_list, "Unsupported order, valid orders: {}".format(", ".join(supported_order_list))
    limit = valid_limit(limit, 1000)
    db = context['db']

    comments = []
    if order == 'by_cashout_time':
        assert len(start) == 3, "Expecting three arguments"
        author = start[1]
        permlink = start[2]
        post_id = 0
        if author or permlink:
            post_id = await get_post_id_by_author_and_permlink(db, author, permlink, 1)

        sql = """SELECT post_id, community_id, author, permlink, title, body, category, depth,
                    promoted, payout, payout_at, is_paidout, children, votes,
                    created_at, updated_at, rshares, json,
                    is_hidden, is_grayed, total_votes, flag_weight,
                    legacy_id, parent_author, parent_permlink, curator_payout_value, 
                    root_author, root_permlink, max_accepted_payout, percent_steem_dollars, 
                    allow_replies, allow_votes, allow_curation_rewards, url, root_title 
               FROM hive_posts_cache WHERE payout_at >= :start AND post_id >= :post_id ORDER BY payout_at ASC, post_id ASC LIMIT :limit"""
        result = await db.query_all(sql, start=start[0], limit=limit, post_id=post_id)
        for row in result:
            comments.append(condenser_post_object(dict(row)))
    elif order == 'by_permlink':
        assert len(start) == 2, "Expecting two arguments"
        sql = """SELECT post_id, community_id, author, permlink, title, body, category, depth,
                    promoted, payout, payout_at, is_paidout, children, votes,
                    created_at, updated_at, rshares, json,
                    is_hidden, is_grayed, total_votes, flag_weight,
                    legacy_id, parent_author, parent_permlink, curator_payout_value, 
                    root_author, root_permlink, max_accepted_payout, percent_steem_dollars, 
                    allow_replies, allow_votes, allow_curation_rewards, url, root_title 
               FROM hive_posts_cache WHERE author >= :author AND permlink >= :permlink ORDER BY author ASC, permlink ASC, post_id ASC LIMIT :limit"""
        result = await db.query_all(sql, author=start[0], permlink=start[1], limit=limit)
        for row in result:
            comments.append(condenser_post_object(dict(row)))
    elif order == 'by_root':
        assert len(start) == 4, "Expecting 4 arguments"

        sql = """SELECT post_id, community_id, author, permlink, title, body, category, depth,
                    promoted, payout, payout_at, is_paidout, children, votes,
                    created_at, updated_at, rshares, json,
                    is_hidden, is_grayed, total_votes, flag_weight,
                    legacy_id, parent_author, parent_permlink, curator_payout_value, 
                    root_author, root_permlink, max_accepted_payout, percent_steem_dollars, 
                    allow_replies, allow_votes, allow_curation_rewards, url, root_title 
               FROM get_rows_by_root(:root_author, :root_permlink, :child_author, :child_permlink) ORDER BY post_id ASC LIMIT :limit"""
        result = await db.query_all(sql, root_author=start[0], root_permlink=start[1], child_author=start[2], child_permlink=start[3], limit=limit)
        for row in result:
            comments.append(condenser_post_object(dict(row)))
    elif order == 'by_parent':
        assert len(start) == 4, "Expecting 4 arguments"

        sql = """SELECT post_id, community_id, author, permlink, title, body, category, depth,
                    promoted, payout, payout_at, is_paidout, children, votes,
                    created_at, updated_at, rshares, json,
                    is_hidden, is_grayed, total_votes, flag_weight,
                    legacy_id, parent_author, parent_permlink, curator_payout_value, 
                    root_author, root_permlink, max_accepted_payout, percent_steem_dollars, 
                    allow_replies, allow_votes, allow_curation_rewards, url, root_title 
               FROM get_rows_by_parent(:parent_author, :parent_permlink, :child_author, :child_permlink) LIMIT :limit"""
        result = await db.query_all(sql, parent_author=start[0], parent_permlink=start[1], child_author=start[2], child_permlink=start[3], limit=limit)
        for row in result:
            comments.append(condenser_post_object(dict(row)))
    elif order == 'by_update':
        assert len(start) == 4, "Expecting 4 arguments"

        child_author = start[2]
        child_permlink = start[3]

        post_id = 0
        if author or permlink:
            post_id = await get_post_id_by_author_and_permlink(db, child_author, child_permlink, 1)

        sql = """SELECT post_id, community_id, author, permlink, title, body, category, depth,
                    promoted, payout, payout_at, is_paidout, children, votes,
                    created_at, updated_at, rshares, json,
                    is_hidden, is_grayed, total_votes, flag_weight,
                    legacy_id, parent_author, parent_permlink, curator_payout_value, 
                    root_author, root_permlink, max_accepted_payout, percent_steem_dollars, 
                    allow_replies, allow_votes, allow_curation_rewards, url, root_title 
               FROM hive_posts_cache WHERE parent_author >= :parent_author AND updated_at >= :updated_at AND post_id >= :post_id ORDER BY parent_author ASC, updated_at ASC, post_id ASC LIMIT :limit"""
        result = await db.query_all(sql, parent_author=start[0], updated_at=start[1], post_id=post_id, limit=limit)
        for row in result:
            comments.append(condenser_post_object(dict(row)))

    elif order == 'by_author_last_update':
        assert len(start) == 4, "Expecting 4 arguments"

        author = start[2]
        permlink = start[3]

        post_id = 0
        if author or permlink:
            post_id = await get_post_id_by_author_and_permlink(db, author, permlink, 1)

        sql = """SELECT post_id, community_id, author, permlink, title, body, category, depth,
                    promoted, payout, payout_at, is_paidout, children, votes,
                    created_at, updated_at, rshares, json,
                    is_hidden, is_grayed, total_votes, flag_weight,
                    legacy_id, parent_author, parent_permlink, curator_payout_value, 
                    root_author, root_permlink, max_accepted_payout, percent_steem_dollars, 
                    allow_replies, allow_votes, allow_curation_rewards, url, root_title 
               FROM hive_posts_cache WHERE author >= :author AND updated_at >= :updated_at AND post_id >= :post_id ORDER BY parent_author ASC, updated_at ASC, post_id ASC LIMIT :limit"""
        result = await db.query_all(sql, author=start[0], updated_at=start[1], post_id=post_id, limit=limit)
        for row in result:
            comments.append(condenser_post_object(dict(row)))

    return comments
