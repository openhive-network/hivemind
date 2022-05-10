# pylint: disable=too-many-arguments,line-too-long,too-many-lines
from enum import Enum

from hive.server.common.helpers import json_date
from hive.server.common.helpers import return_error_info, valid_account, valid_date, valid_limit, valid_permlink
from hive.server.database_api.objects import database_post_object
from hive.utils.normalize import escape_characters

from hive.server.db import Db

from distutils import util


# -*- coding: utf-8 -*-
from jsonrpcserver.exceptions import ApiError

JSON_RPC_SERVER_ERROR       = -32000
JSON_RPC_ERROR_DURING_CALL  = -32003

class SQLExceptionWrapper(ApiError):
  def __init__(self, msg):
    super().__init__(msg, JSON_RPC_ERROR_DURING_CALL)

class InternalServerException(ApiError):
  def __init__(self, msg):
    super().__init__(msg, JSON_RPC_ERROR_DURING_CALL)

class CustomUInt64ParserApiException(ApiError):
  def __init__(self):
    super().__init__("Parse Error:Couldn't parse uint64_t", JSON_RPC_SERVER_ERROR)

class CustomInt64ParserApiException(ApiError):
  def __init__(self):
    super().__init__("Parse Error:Couldn't parse int64_t", JSON_RPC_SERVER_ERROR)

class CustomBoolParserApiException(ApiError):
  def __init__(self):
    super().__init__("Bad Cast:Cannot convert string to bool (only \"true\" or \"false\" can be converted)", JSON_RPC_SERVER_ERROR)


MAX_BIGINT_POSTGRES = 9_223_372_036_854_775_807
ENUM_VIRTUAL_OPS_LIMIT = 150_000
DEFAULT_INCLUDE_IRREVERSIBLE = False
DEFAULT_LIMIT = 1_000
BLOCK_WIDTH_LIMIT = 2 * DEFAULT_LIMIT
RANGEINT = 2**32


def convert(val, default_value):
    try:
        if val is None:
            return default_value

        invalid_val = False
        if isinstance(val, str):
            if(val == "true" or val == "false"):#old code from AH doesn't allow f.e. `True` value
                return bool(util.strtobool(val))
            else:
                invalid_val = True
        elif isinstance(val, int):
            return bool(val)
    except Exception as ex:
        raise CustomBoolParserApiException()

    if invalid_val:
        raise CustomBoolParserApiException()
    else:
        return val

@return_error_info
async def get_ops_in_block( context, block_num : int, only_virtual : bool = None, include_reversible : bool = None):
    try:
        block_num = 0 if block_num is None else int(block_num)
    except Exception:
        raise CustomUInt64ParserApiException()

    include_reversible  = convert(include_reversible, DEFAULT_INCLUDE_IRREVERSIBLE)
    only_virtual        = convert(only_virtual, False)


    db : Db = context['db']
    return await db.query_one(
        "SELECT * FROM hafah_python.get_ops_in_block_json( :block_num, :only_virt, :include_reversible, :is_legacy_style )",
        block_num=block_num,
        only_virt=only_virtual,
        include_reversible=include_reversible,
        is_legacy_style=True
    )

@return_error_info
async def get_transaction(context, id : str, include_reversible : bool = None):
    include_reversible = convert(include_reversible, DEFAULT_INCLUDE_IRREVERSIBLE)

    db : Db = context['db']
    return await db.query_one(
        "SELECT * FROM hafah_python.get_transaction_json( :trx_hash, :include_reversible, :is_legacy_style )",
        trx_hash=f'\\x{id}',
        include_reversible=include_reversible,
        is_legacy_style=True
    )

@return_error_info
async def get_account_history(context, account : str, operation_filter_low : int = None, operation_filter_high : int = None, start : int = None, limit : int = None, include_reversible : bool = None):
    try:
        start                  = -1            if start is None                  else int(start)
        limit                  = DEFAULT_LIMIT if limit is None                  else int(limit)
        operation_filter_low   = 0             if operation_filter_low is None   else int(operation_filter_low)
        operation_filter_high  = 0             if operation_filter_high is None  else int(operation_filter_high)
    except Exception:
        raise CustomUInt64ParserApiException()

    include_reversible = convert(include_reversible, DEFAULT_INCLUDE_IRREVERSIBLE)

    start = start if start >= 0 else MAX_BIGINT_POSTGRES
    limit = (RANGEINT + limit) if limit < 0 else limit

    db : Db = context['db']
    return await db.query_one(
        f"SELECT * FROM hafah_python.ah_get_account_history_json( :filter_low, :filter_high, :account, :start ::BIGINT, :limit, :include_reversible, :is_legacy_style )",
        filter_low=operation_filter_low,
        filter_high=operation_filter_high,
        account=account,
        start=start,
        limit=limit,
        include_reversible=include_reversible,
        is_legacy_style=True
    )

@return_error_info
async def enum_virtual_ops(context, block_range_begin : int, block_range_end : int, operation_begin : int = None, filter : int = None, limit : int = None, include_reversible : bool = None, group_by_block : bool = None):
    try:
        block_range_begin  = int(block_range_begin)
        block_range_end    = int(block_range_end)
        operation_begin    = 0       if operation_begin is None  else int(operation_begin)
        filter             = filter  if filter is None           else int(filter)
    except Exception:
        raise CustomUInt64ParserApiException()

    try:
        limit              = ENUM_VIRTUAL_OPS_LIMIT if limit is None            else int(limit)
    except Exception:
        raise CustomInt64ParserApiException()

    include_reversible  = convert(include_reversible, DEFAULT_INCLUDE_IRREVERSIBLE)
    group_by_block      = convert(group_by_block, False)

    db : Db = context['db']
    return await db.query_one(
        "SELECT * FROM hafah_python.enum_virtual_ops_json( :filter, :block_range_begin, :block_range_end, :operation_begin, :limit, :include_reversible, :group_by_block )",
        filter=filter,
        block_range_begin=block_range_begin,
        block_range_end=block_range_end,
        operation_begin=operation_begin,
        limit=limit,
        include_reversible=include_reversible,
        group_by_block=group_by_block
    )

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
        sql = "SELECT * FROM list_comments_by_cashout_time(:cashout_time, :author, :permlink, :limit)"
        result = await db.query_all(sql, cashout_time=cashout_time, author=author, permlink=permlink, limit=limit)
    elif order == 'by_permlink':
        assert len(start) == 2, "Expecting two arguments in 'start' array: author and permlink"
        author = start[0]
        assert isinstance(author, str), "invalid account name type"
        permlink = start[1]
        assert isinstance(permlink, str), "permlink must be string"
        sql = "SELECT * FROM list_comments_by_permlink(:author, :permlink, :limit)"
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
        sql = "SELECT * FROM list_comments_by_root(:root_author, :root_permlink, :start_post_author, :start_post_permlink, :limit)"
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
        sql = "SELECT * FROM list_comments_by_parent(:parent_author, :parent_permlink, :start_post_author, :start_post_permlink, :limit)"
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
        sql = "SELECT * FROM list_comments_by_last_update(:parent_author, :updated_at, :start_post_author, :start_post_permlink, :limit)"
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
        sql = "SELECT * FROM list_comments_by_author_last_update(:author, :updated_at, :start_post_author, :start_post_permlink, :limit)"
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

    SQL_TEMPLATE = """
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
          live_posts_comments_view hp
        JOIN hive_accounts_view ha_a ON ha_a.id = hp.author_id
        JOIN hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id
        JOIN (VALUES {}) AS t (author, permlink, number) ON ha_a.name = t.author AND hpd_p.permlink = t.permlink
        WHERE
          NOT hp.is_muted
        ORDER BY t.number
      ) ds,
      LATERAL get_post_view_by_id (ds.id) pv
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


@return_error_info
async def find_votes_impl(db, author: str, permlink: str, votes_presentation, limit: int = 1000):
    sql = "SELECT * FROM find_votes(:author,:permlink,:limit)"
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
        sql = "SELECT * FROM list_votes_by_voter_comment(:voter,:author,:permlink,:limit)"
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
        sql = "SELECT * FROM list_votes_by_comment_voter(:voter,:author,:permlink,:limit)"
        rows = await db.query_all(sql, voter=start_voter, author=author, permlink=permlink, limit=limit)
    return {'votes': api_vote_info(rows, VotesPresentation.DatabaseApi)}
