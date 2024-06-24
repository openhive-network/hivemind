# pylint: disable=too-many-arguments,line-too-long,too-many-lines
from enum import Enum

from hive.conf import SCHEMA_NAME
from hive.server.common.helpers import json_date
from hive.server.common.helpers import return_error_info, valid_account, valid_date, valid_limit, valid_permlink
from hive.server.database_api.objects import database_post_object
from hive.utils.normalize import escape_characters


@return_error_info
async def list_comments(context, start: list, limit: int = 1000, order: str = None):
    """Returns all comments, starting with the specified options."""

    supported_order_list = [
        'by_cashout_time',
        'by_permlink',
        'by_root',
        'by_parent',
        'by_last_update',
        'by_author_last_update',
    ]
    assert not order is None, "missing a required argument: 'order'"
    assert order in supported_order_list, f"Unsupported order, valid orders: {', '.join(supported_order_list)}"
    limit = valid_limit(limit, 1000, 1000)
    db = context['db']

    result = []
    if order == 'by_cashout_time':
        assert (
            len(start) == 3
        ), "Expecting three arguments in 'start' array: cashout time, optional page start author and permlink"
        cashout_time = start[0]
        valid_date(cashout_time)
        if cashout_time[0:4] == '1969':
            cashout_time = "infinity"
        author = start[1]
        valid_account(author, allow_empty=True)
        permlink = start[2]
        valid_permlink(permlink, allow_empty=True)
        sql = f"SELECT * FROM {SCHEMA_NAME}.list_comments_by_cashout_time(:cashout_time, :author, :permlink, :limit)"
        result = await db.query_all(sql, cashout_time=cashout_time, author=author, permlink=permlink, limit=limit)
    elif order == 'by_permlink':
        assert len(start) == 2, "Expecting two arguments in 'start' array: author and permlink"
        author = start[0]
        assert isinstance(author, str), "invalid account name type"
        permlink = start[1]
        assert isinstance(permlink, str), "permlink must be string"
        sql = f"SELECT * FROM {SCHEMA_NAME}.list_comments_by_permlink(:author, :permlink, :limit)"
        result = await db.query_all(sql, author=author, permlink=permlink, limit=limit)
    elif order == 'by_root':
        assert (
            len(start) == 4
        ), "Expecting 4 arguments in 'start' array: discussion root author and permlink, optional page start author and permlink"
        root_author = start[0]
        valid_account(root_author)
        root_permlink = start[1]
        valid_permlink(root_permlink)
        start_post_author = start[2]
        valid_account(start_post_author, allow_empty=True)
        start_post_permlink = start[3]
        valid_permlink(start_post_permlink, allow_empty=True)
        sql = f"SELECT * FROM {SCHEMA_NAME}.list_comments_by_root(:root_author, :root_permlink, :start_post_author, :start_post_permlink, :limit)"
        result = await db.query_all(
            sql,
            root_author=root_author,
            root_permlink=root_permlink,
            start_post_author=start_post_author,
            start_post_permlink=start_post_permlink,
            limit=limit,
        )
    elif order == 'by_parent':
        assert (
            len(start) == 4
        ), "Expecting 4 arguments in 'start' array: parent post author and permlink, optional page start author and permlink"
        parent_author = start[0]
        valid_account(parent_author)
        parent_permlink = start[1]
        valid_permlink(parent_permlink)
        start_post_author = start[2]
        valid_account(start_post_author, allow_empty=True)
        start_post_permlink = start[3]
        valid_permlink(start_post_permlink, allow_empty=True)
        sql = f"SELECT * FROM {SCHEMA_NAME}.list_comments_by_parent(:parent_author, :parent_permlink, :start_post_author, :start_post_permlink, :limit)"
        result = await db.query_all(
            sql,
            parent_author=parent_author,
            parent_permlink=parent_permlink,
            start_post_author=start_post_author,
            start_post_permlink=start_post_permlink,
            limit=limit,
        )
    elif order == 'by_last_update':
        assert (
            len(start) == 4
        ), "Expecting 4 arguments in 'start' array: parent author, update time, optional page start author and permlink"
        parent_author = start[0]
        valid_account(parent_author)
        updated_at = start[1]
        valid_date(updated_at)
        start_post_author = start[2]
        valid_account(start_post_author, allow_empty=True)
        start_post_permlink = start[3]
        valid_permlink(start_post_permlink, allow_empty=True)
        sql = f"SELECT * FROM {SCHEMA_NAME}.list_comments_by_last_update(:parent_author, :updated_at, :start_post_author, :start_post_permlink, :limit)"
        result = await db.query_all(
            sql,
            parent_author=parent_author,
            updated_at=updated_at,
            start_post_author=start_post_author,
            start_post_permlink=start_post_permlink,
            limit=limit,
        )
    elif order == 'by_author_last_update':
        assert (
            len(start) == 4
        ), "Expecting 4 arguments in 'start' array: author, update time, optional page start author and permlink"
        author = start[0]
        valid_account(author)
        updated_at = start[1]
        valid_date(updated_at)
        start_post_author = start[2]
        valid_account(start_post_author, allow_empty=True)
        start_post_permlink = start[3]
        valid_permlink(start_post_permlink, allow_empty=True)
        sql = f"SELECT * FROM {SCHEMA_NAME}.list_comments_by_author_last_update(:author, :updated_at, :start_post_author, :start_post_permlink, :limit)"
        result = await db.query_all(
            sql,
            author=author,
            updated_at=updated_at,
            start_post_author=start_post_author,
            start_post_permlink=start_post_permlink,
            limit=limit,
        )

    return {"comments": [database_post_object(dict(row)) for row in result]}


@return_error_info
async def find_comments(context, comments: list):
    """Search for comments: limit and order is ignored in hive code"""
    result = []

    assert isinstance(comments, list), "Expected array of author+permlink pairs"
    assert len(comments) <= 1000, "Parameters count is greather than max allowed (1000)"
    db = context['db']

    SQL_TEMPLATE = f"""
      SELECT
        pv.id,
        pv.community_id,
        pv.author,
        pv.permlink,
        pv.title,
        pv.body,
        pv.category,
        pv.depth,
        pv.promoted,
        pv.payout,
        pv.last_payout_at,
        pv.cashout_time,
        pv.is_paidout,
        pv.children,
        pv.votes,
        pv.created_at,
        pv.updated_at,
        pv.rshares,
        pv.json,
        pv.is_hidden,
        pv.is_grayed,
        pv.total_votes,
        pv.net_votes,
        pv.total_vote_weight,
        pv.parent_permlink_or_category,
        pv.curator_payout_value,
        pv.root_author,
        pv.root_permlink,
        pv.max_accepted_payout,
        pv.percent_hbd,
        pv.allow_replies,
        pv.allow_votes,
        pv.allow_curation_rewards,
        pv.beneficiaries,
        pv.url,
        pv.root_title,
        pv.abs_rshares,
        pv.active,
        pv.author_rewards,
        pv.parent_author
      FROM (
        SELECT
          hp.id
        FROM
          {SCHEMA_NAME}.live_posts_comments_view hp
        JOIN {SCHEMA_NAME}.hive_accounts ha_a ON ha_a.id = hp.author_id
        JOIN {SCHEMA_NAME}.hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id
        JOIN (VALUES {{}}) AS t (author, permlink, number) ON ha_a.name = t.author AND hpd_p.permlink = t.permlink
        WHERE
          NOT hp.is_muted
        ORDER BY t.number
      ) ds,
      LATERAL {SCHEMA_NAME}.get_post_view_by_id (ds.id) pv
    """

    idx = 0
    values = ""
    for arg in comments:
        if not isinstance(arg, list) or len(arg) < 2:
            continue
        author = arg[0]
        permlink = arg[1]
        if not isinstance(author, str) or not isinstance(permlink, str):
            continue
        if idx > 0:
            values += ","
        values += f"({escape_characters(author)},{escape_characters(permlink)},{idx})"
        idx += 1
    sql = SQL_TEMPLATE.format(values)

    if idx > 0:
        rows = await db.query_all(sql)
        for row in rows:
            cpo = database_post_object(dict(row))
            result.append(cpo)

    return {"comments": result}


class VotesPresentation(Enum):
    ActiveVotes = 1
    DatabaseApi = 2
    CondenserApi = 3
    BridgeApi = 4


def api_vote_info(rows, votes_presentation):
    ret = []
    for row in rows:
        if votes_presentation == VotesPresentation.DatabaseApi:
            ret.append(
                dict(
                    id=row.id,
                    voter=row.voter,
                    author=row.author,
                    permlink=row.permlink,
                    weight=row.weight,
                    rshares=row.rshares,
                    vote_percent=row.percent,
                    last_update=json_date(row.last_update),
                    num_changes=row.num_changes,
                )
            )
        elif votes_presentation == VotesPresentation.CondenserApi:
            ret.append(dict(percent=str(row.percent), reputation=row.reputation, rshares=row.rshares, voter=row.voter))
        elif votes_presentation == VotesPresentation.BridgeApi:
            ret.append(dict(rshares=row.rshares, voter=row.voter))
        else:
            ret.append(
                dict(
                    percent=row.percent,
                    reputation=row.reputation,
                    rshares=row.rshares,
                    time=json_date(row.last_update),
                    voter=row.voter,
                    weight=row.weight,
                )
            )
    return ret


async def find_votes_impl(db, author: str, permlink: str, votes_presentation, limit: int = 1000):
    sql = f"SELECT * FROM {SCHEMA_NAME}.find_votes(:author,:permlink,:limit)"
    rows = await db.query_all(sql, author=author, permlink=permlink, limit=limit)
    return api_vote_info(rows, votes_presentation)


@return_error_info
async def find_votes(context, author: str, permlink: str):
    """Returns all votes for the given post"""
    valid_account(author)
    valid_permlink(permlink)
    return {'votes': await find_votes_impl(context['db'], author, permlink, VotesPresentation.DatabaseApi)}


@return_error_info
async def list_votes(context, start: list, limit: int = 1000, order: str = None):
    """Returns all votes, starting with the specified voter and/or author and permlink."""
    supported_order_list = ["by_comment_voter", "by_voter_comment"]
    assert not order is None, "missing a required argument: 'order'"
    assert order in supported_order_list, f"Unsupported order, valid orders: {', '.join(supported_order_list)}"
    limit = valid_limit(limit, 1000, 1000)
    db = context['db']

    if order == "by_voter_comment":
        assert len(start) == 3, "Expecting 3 arguments in 'start' array: voter, optional page start author and permlink"
        voter = start[0]
        valid_account(voter)
        start_post_author = start[1]
        valid_account(start_post_author, allow_empty=True)
        start_post_permlink = start[2]
        valid_permlink(start_post_permlink, allow_empty=True)
        sql = f"SELECT * FROM {SCHEMA_NAME}.list_votes_by_voter_comment(:voter,:author,:permlink,:limit)"
        rows = await db.query_all(sql, voter=voter, author=start_post_author, permlink=start_post_permlink, limit=limit)
    else:
        assert (
            len(start) == 3
        ), "Expecting 3 arguments in 'start' array: post author and permlink, optional page start voter"
        author = start[0]
        valid_account(author)
        permlink = start[1]
        valid_permlink(permlink)
        start_voter = start[2]
        valid_account(start_voter, allow_empty=True)
        sql = f"SELECT * FROM {SCHEMA_NAME}.list_votes_by_comment_voter(:voter,:author,:permlink,:limit)"
        rows = await db.query_all(sql, voter=start_voter, author=author, permlink=permlink, limit=limit)
    return {'votes': api_vote_info(rows, VotesPresentation.DatabaseApi)}
