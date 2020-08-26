# pylint: disable=too-many-arguments,line-too-long,too-many-lines
from enum import Enum

from hive.server.common.helpers import return_error_info, valid_limit, valid_account, valid_permlink
from hive.server.database_api.objects import database_post_object
from hive.utils.normalize import rep_to_raw, number_to_json_value, time_string_with_t

import datetime

@return_error_info
async def list_comments(context, start: list, limit: int, order: str):
    """Returns all comments, starting with the specified options."""

    supported_order_list = ['by_cashout_time', 'by_permlink', 'by_root', 'by_parent', 'by_last_update', 'by_author_last_update']
    assert order in supported_order_list, "Unsupported order, valid orders: {}".format(", ".join(supported_order_list))
    limit = valid_limit(limit, 1000)
    db = context['db']

    result = []
    if order == 'by_cashout_time':
        assert len(start) == 3, "Expecting three arguments"
        cashout_time = start[0]
        if cashout_time[0:4] == '1969':
            cashout_time = "infinity"
        author = start[1]
        permlink = start[2]
        sql = "SELECT * FROM list_comments_by_cashout_time(:cashout_time, :author, :permlink, :limit)"
        result = await db.query_all(sql, cashout_time=cashout_time, author=author, permlink=permlink, limit=limit)
    elif order == 'by_permlink':
        assert len(start) == 2, "Expecting two arguments"
        author = start[0]
        permlink = start[1]
        sql = "SELECT * FROM list_comments_by_permlink(:author, :permlink, :limit)"
        result = await db.query_all(sql, author=author, permlink=permlink, limit=limit)
    elif order == 'by_root':
        assert len(start) == 4, "Expecting 4 arguments"
        root_author = start[0]
        root_permlink = start[1]
        start_post_author = start[2]
        start_post_permlink = start[3]
        sql = "SELECT * FROM list_comments_by_root(:root_author, :root_permlink, :start_post_author, :start_post_permlink, :limit)"
        result = await db.query_all(sql, root_author=root_author, root_permlink=root_permlink, start_post_author=start_post_author, start_post_permlink=start_post_permlink, limit=limit)
    elif order == 'by_parent':
        assert len(start) == 4, "Expecting 4 arguments"
        parent_author = start[0]
        parent_permlink = start[1]
        start_post_author = start[2]
        start_post_permlink = start[3]
        sql = "SELECT * FROM list_comments_by_parent(:parent_author, :parent_permlink, :start_post_author, :start_post_permlink, :limit)"
        result = await db.query_all(sql, parent_author=parent_author, parent_permlink=parent_permlink, start_post_author=start_post_author, start_post_permlink=start_post_permlink, limit=limit)
    elif order == 'by_last_update':
        assert len(start) == 4, "Expecting 4 arguments"
        parent_author = start[0]
        updated_at = start[1]
        start_post_author = start[2]
        start_post_permlink = start[3]
        sql = "SELECT * FROM list_comments_by_last_update(:parent_author, :updated_at, :start_post_author, :start_post_permlink, :limit)"
        result = await db.query_all(sql, parent_author=parent_author, updated_at=updated_at, start_post_author=start_post_author, start_post_permlink=start_post_permlink, limit=limit)
    elif order == 'by_author_last_update':
        assert len(start) == 4, "Expecting 4 arguments"
        author = start[0]
        updated_at = start[1]
        start_post_author = start[2]
        start_post_permlink = start[3]
        sql = "SELECT * FROM list_comments_by_author_last_update(:author, :updated_at, :start_post_author, :start_post_permlink, :limit)"
        result = await db.query_all(sql, author=author, updated_at=updated_at, start_post_author=start_post_author, start_post_permlink=start_post_permlink, limit=limit)

    return { "comments": [database_post_object(dict(row)) for row in result] }

@return_error_info
async def find_comments(context, comments: list):
    """ Search for comments: limit and order is ignored in hive code """
    result = []

    assert len(comments) <= 1000, "Parameters count is greather than max allowed (1000)"
    db = context['db']

    SQL_TEMPLATE = """
        SELECT
            hp.id,
            hp.community_id,
            hp.author,
            hp.permlink,
            hp.title,
            hp.body,
            hp.category,
            hp.depth,
            hp.promoted,
            hp.payout,
            hp.last_payout_at,
            hp.cashout_time,
            hp.is_paidout,
            hp.children,
            hp.votes,
            hp.created_at,
            hp.updated_at,
            hp.rshares,
            hp.json,
            hp.is_hidden,
            hp.is_grayed,
            hp.total_votes,
            hp.net_votes,
            hp.total_vote_weight,
            hp.parent_author,
            hp.parent_permlink_or_category,
            hp.curator_payout_value,
            hp.root_author,
            hp.root_permlink,
            hp.max_accepted_payout,
            hp.percent_hbd,
            hp.allow_replies,
            hp.allow_votes,
            hp.allow_curation_rewards,
            hp.beneficiaries,
            hp.url,
            hp.root_title,
            hp.abs_rshares,
            hp.active,
            hp.author_rewards
        FROM
            hive_posts_view hp
        JOIN (VALUES {}) AS t (author, permlink) ON hp.author = t.author AND hp.permlink = t.permlink
        WHERE
            NOT hp.is_muted AND hp.counter_deleted = 0
    """

    idx = 0
    values = ""
    for arg in comments:
        if idx > 0:
            values += ","
        values += "('{}','{}')".format(arg[0], arg[1])
        idx += 1
    sql = SQL_TEMPLATE.format(values)

    rows = await db.query_all(sql)
    for row in rows:
        cpo = database_post_object(dict(row))
        result.append(cpo)

    return { "comments": result }

class VotesPresentation(Enum):
    ActiveVotes = 1
    DatabaseApi = 2
    CondenserApi = 3
    BridgeApi = 4

@return_error_info
async def find_votes(context, params: dict, votes_presentation = VotesPresentation.DatabaseApi):
    """ Returns all votes for the given post """
    valid_account(params['author'])
    valid_permlink(params['permlink'])
    db = context['db']
    sql = """
        SELECT
            voter,
            author,
            permlink,
            weight,
            rshares,
            percent,
            time,
            num_changes,
            reputation
        FROM
            hive_votes_accounts_permlinks_view
        WHERE
            author = :author AND permlink = :permlink
        ORDER BY 
            voter_id
    """

    ret = []
    rows = await db.query_all(sql, author=params['author'], permlink=params['permlink'])

    for row in rows:
        if votes_presentation == VotesPresentation.DatabaseApi:
            ret.append(dict(voter=row.voter, author=row.author, permlink=row.permlink,
                            weight=row.weight, rshares=row.rshares, vote_percent=row.percent,
                            last_update=str(row.time), num_changes=row.num_changes))
        elif votes_presentation == VotesPresentation.CondenserApi:
            ret.append(dict(percent=str(row.percent), reputation=rep_to_raw(row.reputation),
                            rshares=str(row.rshares), voter=row.voter))
        elif votes_presentation == VotesPresentation.BridgeApi:
            ret.append(dict(rshares=str(row.rshares), voter=row.voter))
        else:
            ret.append(dict(percent=row.percent, reputation=rep_to_raw(row.reputation),
                            rshares=number_to_json_value(row.rshares), time=time_string_with_t(row.time), 
                            voter=row.voter, weight=number_to_json_value(row.weight)
                            ))
    return ret

@return_error_info
async def list_votes(context, start: list, limit: int, order: str):
    """ Returns all votes, starting with the specified voter and/or author and permlink. """
    supported_order_list = ["by_comment_voter", "by_voter_comment"]
    assert order in supported_order_list, "Order {} is not supported".format(order)
    limit = valid_limit(limit, 1000)
    assert len(start) == 3, "Expecting 3 elements in start array"
    db = context['db']

    sql = """
        SELECT
            voter,
            author,
            permlink,
            weight,
            rshares,
            percent,
            time,
            num_changes,
            reputation
        FROM
            hive_votes_accounts_permlinks_view
    """

    if order == "by_comment_voter": # ABW: wrong! fat node sorted by ( comment_id, voter_id )
        sql += """
            WHERE
                author >= :author AND 
                permlink >= :permlink AND 
                voter >= :voter
            ORDER BY
                author ASC, 
                permlink ASC, 
                id ASC 
            LIMIT 
                :limit
        """
        return await db.query_all(sql, author=start[0], permlink=start[1], voter=start[2], limit=limit)
    if order == "by_voter_comment": # ABW: wrong! fat node sorted by ( voter_id, comment_id )
        sql += """
            WHERE
                voter >= :voter AND 
                author >= :author AND 
                permlink >= :permlink
            ORDER BY 
                voter ASC,
                id ASC
            LIMIT
                :limit
        """
        return await db.query_all(sql, author=start[1], permlink=start[2], voter=start[0], limit=limit)
    return []
