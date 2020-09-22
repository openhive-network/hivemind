# pylint: disable=too-many-arguments,line-too-long,too-many-lines
from enum import Enum

from hive.server.common.helpers import return_error_info, valid_limit, valid_account, valid_permlink, valid_date
from hive.server.database_api.objects import database_post_object
from hive.utils.normalize import rep_to_raw, time_string_with_t
from hive.server.common.helpers import json_date

import datetime

@return_error_info
async def list_comments(context, start: list, limit: int, order: str):
    """Returns all comments, starting with the specified options."""

    supported_order_list = ['by_cashout_time', 'by_permlink', 'by_root', 'by_parent', 'by_last_update', 'by_author_last_update']
    assert order in supported_order_list, "Unsupported order, valid orders: {}".format(", ".join(supported_order_list))
    limit = valid_limit(limit, 1000, None)
    db = context['db']

    result = []
    if order == 'by_cashout_time':
        assert len(start) == 3, "Expecting three arguments"
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
        assert len(start) == 2, "Expecting two arguments"
        author = start[0]
        valid_account(author, allow_empty=True)
        permlink = start[1]
        valid_permlink(permlink, allow_empty=True)
        sql = "SELECT * FROM list_comments_by_permlink(:author, :permlink, :limit)"
        result = await db.query_all(sql, author=author, permlink=permlink, limit=limit)
    elif order == 'by_root':
        assert len(start) == 4, "Expecting 4 arguments"
        root_author = start[0]
        valid_account(root_author)
        root_permlink = start[1]
        valid_permlink(root_permlink)
        start_post_author = start[2]
        valid_account(start_post_author, allow_empty=True)
        start_post_permlink = start[3]
        valid_permlink(start_post_permlink, allow_empty=True)
        sql = "SELECT * FROM list_comments_by_root(:root_author, :root_permlink, :start_post_author, :start_post_permlink, :limit)"
        result = await db.query_all(sql, root_author=root_author, root_permlink=root_permlink, start_post_author=start_post_author, start_post_permlink=start_post_permlink, limit=limit)
    elif order == 'by_parent':
        assert len(start) == 4, "Expecting 4 arguments"
        parent_author = start[0]
        valid_account(parent_author)
        parent_permlink = start[1]
        valid_permlink(parent_permlink)
        start_post_author = start[2]
        valid_account(start_post_author, allow_empty=True)
        start_post_permlink = start[3]
        valid_permlink(start_post_permlink, allow_empty=True)
        sql = "SELECT * FROM list_comments_by_parent(:parent_author, :parent_permlink, :start_post_author, :start_post_permlink, :limit)"
        result = await db.query_all(sql, parent_author=parent_author, parent_permlink=parent_permlink, start_post_author=start_post_author, start_post_permlink=start_post_permlink, limit=limit)
    elif order == 'by_last_update':
        assert len(start) == 4, "Expecting 4 arguments"
        parent_author = start[0]
        valid_account(parent_author)
        updated_at = start[1]
        valid_date(updated_at)
        start_post_author = start[2]
        valid_account(start_post_author, allow_empty=True)
        start_post_permlink = start[3]
        valid_permlink(start_post_permlink, allow_empty=True)
        sql = "SELECT * FROM list_comments_by_last_update(:parent_author, :updated_at, :start_post_author, :start_post_permlink, :limit)"
        result = await db.query_all(sql, parent_author=parent_author, updated_at=updated_at, start_post_author=start_post_author, start_post_permlink=start_post_permlink, limit=limit)
    elif order == 'by_author_last_update':
        assert len(start) == 4, "Expecting 4 arguments"
        author = start[0]
        valid_account(author)
        updated_at = start[1]
        valid_date(updated_at)
        start_post_author = start[2]
        valid_account(start_post_author, allow_empty=True)
        start_post_permlink = start[3]
        valid_permlink(start_post_permlink, allow_empty=True)
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
            NOT hp.is_muted
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

def api_vote_info(rows, votes_presentation):
  ret = []
  for row in rows:
      if votes_presentation == VotesPresentation.DatabaseApi:
          ret.append(dict(id = row.id, voter = row.voter, author = row.author, permlink = row.permlink,
                          weight = row.weight, rshares = row.rshares, vote_percent = row.percent,
                          last_update = json_date(row.last_update), num_changes = row.num_changes))
      elif votes_presentation == VotesPresentation.CondenserApi:
          ret.append(dict(percent = str(row.percent), reputation = rep_to_raw(row.reputation),
                          rshares = row.rshares, voter = row.voter))
      elif votes_presentation == VotesPresentation.BridgeApi:
          ret.append(dict(rshares = row.rshares, voter = row.voter))
      else:
          ret.append(dict(percent = row.percent, reputation = rep_to_raw(row.reputation),
                          rshares = row.rshares, time = json_date(row.last_update), 
                          voter = row.voter, weight = row.weight
                          ))
  return ret

@return_error_info
async def find_votes_impl(db, author: str, permlink: str, votes_presentation):
    sql = "SELECT * FROM find_votes(:author,:permlink)"
    rows = await db.query_all(sql, author=author, permlink=permlink)
    return api_vote_info(rows, votes_presentation)

@return_error_info
async def find_votes(context, author: str, permlink: str):
    """ Returns all votes for the given post """
    valid_account(author)
    valid_permlink(permlink)
    return { 'votes': await find_votes_impl(context['db'], author, permlink, VotesPresentation.DatabaseApi) }

@return_error_info
async def list_votes(context, start: list, limit: int, order: str):
    """ Returns all votes, starting with the specified voter and/or author and permlink. """
    supported_order_list = ["by_comment_voter", "by_voter_comment"]
    assert order in supported_order_list, "Order {} is not supported".format(order)
    limit = valid_limit(limit, 1000, None)
    assert len(start) == 3, "Expecting 3 elements in start array"
    db = context['db']

    if order == "by_voter_comment":
        sql = "SELECT * FROM list_votes_by_voter_comment(:voter,:author,:permlink,:limit)"
        rows = await db.query_all(sql, voter=start[0], author=start[1], permlink=start[2], limit=limit)
    else:
        sql = "SELECT * FROM list_votes_by_comment_voter(:voter,:author,:permlink,:limit)"
        rows = await db.query_all(sql, voter=start[2], author=start[0], permlink=start[1], limit=limit)
    return { 'votes': api_vote_info(rows, VotesPresentation.DatabaseApi) }

