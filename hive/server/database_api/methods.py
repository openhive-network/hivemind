# pylint: disable=too-many-arguments,line-too-long,too-many-lines
from hive.server.common.helpers import return_error_info, valid_limit, valid_account, valid_permlink
from hive.server.common.objects import condenser_post_object

SQL_TEMPLATE = """
    SELECT hp.id, 
        community_id, 
        ha_a.name as author,
        hpd_p.permlink as permlink,
        (SELECT title FROM hive_post_data WHERE hive_post_data.id = hp.id) as title, 
        (SELECT body FROM hive_post_data WHERE hive_post_data.id = hp.id) as body, 
        (SELECT category FROM hive_category_data WHERE hive_category_data.id = hp.category_id) as category,
        depth,
        promoted, 
        payout, 
        payout_at, 
        is_paidout, 
        children, 
        (0) as votes,
        hp.created_at, 
        updated_at, 
        rshares, 
        (SELECT json FROM hive_post_data WHERE hive_post_data.id = hp.id) as json,
        is_hidden, 
        is_grayed, 
        total_votes, 
        flag_weight,
        ha_pa.name as parent_author,
        hpd_pp.permlink as parent_permlink,
        curator_payout_value, 
        ha_ra.name as root_author,
        hpd_rp.permlink as root_permlink,
        max_accepted_payout, 
        percent_steem_dollars, 
        allow_replies, 
        allow_votes, 
        allow_curation_rewards, 
        beneficiaries, 
        url, 
        root_title
    FROM hive_posts hp
    INNER JOIN hive_accounts ha_a ON ha_a.id = hp.author_id
    INNER JOIN hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id
    INNER JOIN hive_accounts ha_pa ON ha_pa.id = hp.parent_author_id
    INNER JOIN hive_permlink_data hpd_pp ON hpd_pp.id = hp.parent_permlink_id
    INNER JOIN hive_accounts ha_ra ON ha_ra.id = hp.root_author_id
    INNER JOIN hive_permlink_data hpd_rp ON hpd_rp.id = hp.root_permlink_id
    WHERE
"""

async def get_post_id_by_author_and_permlink(db, author: str, permlink: str, limit: int):
    """Return post ids for given author and permlink"""
    sql = """
        SELECT hp.id 
        FROM hive_posts hp
        INNER JOIN hive_accounts ha_a ON ha_a.id = hp.author_id
        INNER JOIN hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id
        WHERE ha_a.name >= :author AND hpd_p.permlink >= :permlink 
        ORDER BY ha_a.name ASC 
        LIMIT :limit
    """
    result = await db.query_row(sql, author=author, permlink=permlink, limit=limit)
    if result is not None:
        return int(result.get('id', 0))
    return 0

@return_error_info
async def list_comments(context, start: list, limit: int, order: str):
    """Returns all comments, starting with the specified options."""

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

        sql = str(SQL_TEMPLATE)
        sql += "hp.payout_at >= :start AND hp.id >= :post_id ORDER BY hp.payout_at ASC, hp.id ASC LIMIT :limit"

        result = await db.query_all(sql, start=start[0], limit=limit, post_id=post_id)
        for row in result:
            cpo = condenser_post_object(dict(row))
            cpo['active_votes'] = find_votes(context, {'author':cpo['author'], 'permlink':cpo['permlink']})
            comments.append(cpo)
    elif order == 'by_permlink':
        assert len(start) == 2, "Expecting two arguments"

        sql = str(SQL_TEMPLATE)
        sql += """ hp.id IN (SELECT hp1.id FROM hive_posts_a_p hp1 WHERE hp1.author >= :author COLLATE "C" 
          AND hp1.permlink >= :permlink COLLATE "C" ORDER BY hp1.author COLLATE "C" ASC LIMIT :limit)"""

        result = await db.query_all(sql, author=start[0], permlink=start[1], limit=limit)
        for row in result:
            cpo = condenser_post_object(dict(row))
            cpo['active_votes'] = find_votes(context, {'author':cpo['author'], 'permlink':cpo['permlink']})
            comments.append(cpo)
    elif order == 'by_root':
        assert len(start) == 4, "Expecting 4 arguments"
        raise NotImplementedError('by_root')

        sql = str(SQL_TEMPLATE)
        sql += "get_rows_by_root(:root_author, :root_permlink, :child_author, :child_permlink) ORDER BY post_id ASC LIMIT :limit"

        result = await db.query_all(sql, root_author=start[0], root_permlink=start[1], child_author=start[2], child_permlink=start[3], limit=limit)
        for row in result:
            cpo = condenser_post_object(dict(row))
            cpo['active_votes'] = find_votes(context, {'author':cpo['author'], 'permlink':cpo['permlink']})
            comments.append(cpo)
    elif order == 'by_parent':
        assert len(start) == 4, "Expecting 4 arguments"
        raise NotImplementedError('by_parent')

        sql = str(SQL_TEMPLATE)
        sql += "get_rows_by_parent(:parent_author, :parent_permlink, :child_author, :child_permlink) LIMIT :limit"

        result = await db.query_all(sql, parent_author=start[0], parent_permlink=start[1], child_author=start[2], child_permlink=start[3], limit=limit)
        for row in result:
            cpo = condenser_post_object(dict(row))
            cpo['active_votes'] = find_votes(context, {'author':cpo['author'], 'permlink':cpo['permlink']})
            comments.append(cpo)
    elif order == 'by_update':
        assert len(start) == 4, "Expecting 4 arguments"

        child_author = start[2]
        child_permlink = start[3]

        post_id = 0
        if author or permlink:
            post_id = await get_post_id_by_author_and_permlink(db, child_author, child_permlink, 1)

        sql = str(SQL_TEMPLATE)
        sql += "ha_pa.name >= :parent_author AND hp.updated_at >= :updated_at AND hp.id >= :post_id ORDER BY ha_pa.name ASC, updated_at ASC, hp.id ASC LIMIT :limit"

        result = await db.query_all(sql, parent_author=start[0], updated_at=start[1], post_id=post_id, limit=limit)
        for row in result:
            cpo = condenser_post_object(dict(row))
            cpo['active_votes'] = find_votes(context, {'author':cpo['author'], 'permlink':cpo['permlink']})
            comments.append(cpo)

    elif order == 'by_author_last_update':
        assert len(start) == 4, "Expecting 4 arguments"

        author = start[2]
        permlink = start[3]

        post_id = 0
        if author or permlink:
            post_id = await get_post_id_by_author_and_permlink(db, author, permlink, 1)

        sql = str(SQL_TEMPLATE)
        sql += "ha_a.name >= :author AND hp.updated_at >= :updated_at AND hp.id >= :post_id ORDER BY ha_a.name ASC, hp.updated_at ASC, hp.id ASC LIMIT :limit"

        result = await db.query_all(sql, author=start[0], updated_at=start[1], post_id=post_id, limit=limit)
        for row in result:
            cpo = condenser_post_object(dict(row))
            cpo['active_votes'] = find_votes(context, {'author':cpo['author'], 'permlink':cpo['permlink']})
            comments.append(cpo)

    return comments

@return_error_info
async def find_comments(context, start: list, limit: int, order: str):
    """ Search for comments: limit and order is ignored in hive code """
    comments = []

    assert len(start) <= 1000, "Parameters count is greather than max allowed (1000)"
    db = context['db']

    # make a copy
    sql = str(SQL_TEMPLATE)

    idx = 0
    for arg in start:
        if idx > 0:
            sql += " OR "
        sql += "(ha_a.name = '{}' AND hpd_p.permlink = '{}')".format(arg[0], arg[1])
        idx += 1

    result = await db.query_all(sql)
    for row in result:
        cpo = condenser_post_object(dict(row))
        cpo['active_votes'] = find_votes(context, {'author':cpo['author'], 'permlink':cpo['permlink']})
        comments.append(cpo)

    return comments

@return_error_info
async def find_votes(context, params: dict):
    """ Returns all votes for the given post """
    valid_account(params['author'])
    valid_permlink(params['permlink'])
    db = context['db']
    sql = """
        SELECT
            ha_v.name as voter,
            ha_a.name as author,
            hpd.permlink as permlink,
            weight,
            rshares,
            vote_percent,
            last_update,
            num_changes
        FROM
            hive_votes
        INNER JOIN hive_accounts ha_v ON (ha_v.id = hv.voter_id)
        INNER JOIN hive_accounts ha_a ON (ha_a.id = hv.author_id)
        INNER JOIN hive_permlink_data hpd ON (hpd.id = hv.permlink_id)
        WHERE
            ha_a.name = :author AND hpd.permlink = :permlink
    """
    ret = []
    rows = db.query_all(sql, author=params['author'], permlink=params['permlink'])
    for row in rows:
        ret.append(dict(voter=row.voter, author=row.author, permlink=row.permlink,
                        weight=row.weight, rshares=row.rshares, vote_percent=row.vote_percent,
                        last_update=row.last_update, num_changes=row.num_changes))
    return ret

@return_error_info
async def list_votes(context, start: list, limit: int, order: str):
    """ Returns all votes, starting with the specified voter and/or author and permlink. """
    supported_order_list = ["by_comment_voter", "by_voter_comment", "by_comment_voter", "by_voter_comment"]
    assert order in supported_order_list, "Order {} is not supported".format(order)
    limit = valid_limit(limit, 1000)
    assert len(start) == 3, "Expecting 3 elements in start array"
