"""Steemd/condenser_api compatibility layer API methods."""
from json import loads
from functools import wraps

import hive.server.condenser_api.cursor as cursor
from hive.server.condenser_api.objects import load_posts, load_posts_reblogs
from hive.server.condenser_api.objects import _mute_votes, _condenser_post_object
from hive.server.common.helpers import (
    ApiError,
    return_error_info,
    valid_account,
    valid_permlink,
    valid_tag,
    valid_offset,
    valid_limit,
    valid_follow_type)
from hive.server.common.mutes import Mutes
from hive.server.database_api.methods import find_votes_impl, VotesPresentation
from hive.utils.normalize import time_string_with_t

# pylint: disable=too-many-arguments,line-too-long,too-many-lines

SQL_TEMPLATE = """
    SELECT
        hp.id,
        hp.author,
        hp.permlink,
        hp.author_rep,
        hp.title,
        hp.body,
        hp.category,
        hp.depth,
        hp.promoted,
        hp.payout,
        hp.pending_payout,
        hp.payout_at,
        hp.is_paidout,
        hp.children,
        hp.votes,
        hp.created_at,
        hp.updated_at,
        hp.rshares,
        hp.abs_rshares,
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
        hp.active,
        hp.author_rewards
    FROM hive_posts_view hp
"""

@return_error_info
async def get_account_votes(context, account):
    """Return an info message about get_acccount_votes being unsupported."""
    # pylint: disable=unused-argument
    assert False, "get_account_votes is no longer supported, for details see https://hive.blog/steemit/@steemitdev/additional-public-api-change"


# Follows Queries

def _legacy_follower(follower, following, follow_type):
    return dict(follower=follower, following=following, what=[follow_type])

@return_error_info
async def get_followers(context, account: str, start: str, follow_type: str = None,
                        limit: int = None, **kwargs):
    """Get all accounts following `account`. (EOL)"""
    # `type` reserved word workaround
    if not follow_type and 'type' in kwargs:
        follow_type = kwargs['type']
    if not follow_type:
        follow_type = 'blog'
    followers = await cursor.get_followers(
        context['db'],
        valid_account(account),
        valid_account(start, allow_empty=True),
        valid_follow_type(follow_type),
        valid_limit(limit, 1000, None))
    return [_legacy_follower(name, account, follow_type) for name in followers]

@return_error_info
async def get_following(context, account: str, start: str, follow_type: str = None,
                        limit: int = None, **kwargs):
    """Get all accounts `account` follows. (EOL)"""
    # `type` reserved word workaround
    if not follow_type and 'type' in kwargs:
        follow_type = kwargs['type']
    if not follow_type:
        follow_type = 'blog'
    following = await cursor.get_following(
        context['db'],
        valid_account(account),
        valid_account(start, allow_empty=True),
        valid_follow_type(follow_type),
        valid_limit(limit, 1000, None))
    return [_legacy_follower(account, name, follow_type) for name in following]

@return_error_info
async def get_follow_count(context, account: str):
    """Get follow count stats. (EOL)"""
    count = await cursor.get_follow_counts(
        context['db'],
        valid_account(account))
    return dict(account=account,
                following_count=count['following'],
                follower_count=count['followers'])

@return_error_info
async def get_reblogged_by(context, author: str, permlink: str):
    """Get all rebloggers of a post."""
    return await cursor.get_reblogged_by(
        context['db'],
        valid_account(author),
        valid_permlink(permlink))

@return_error_info
async def get_account_reputations(context, account_lower_bound: str = None, limit: int = None):
    db = context['db']
    return await _get_account_reputations_impl(db, True, account_lower_bound, limit)

async def _get_account_reputations_impl(db, fat_node_style, account_lower_bound, limit):
    """Enumerate account reputations."""
    limit = valid_limit(limit, 1000, None)
    seek = ''
    if account_lower_bound:
        seek = "WHERE name >= :start"

    sql = """SELECT name, reputation
              FROM hive_accounts %s
           ORDER BY name
              LIMIT :limit""" % seek

    rows = await db.query_all(sql, start=account_lower_bound, limit=limit)
    if fat_node_style:
        return [dict(account=r[0], reputation=r[1]) for r in rows]
    else:
        return {'reputations': [dict(name=r[0], reputation=r[1]) for r in rows]}

# Content Primitives

@return_error_info
async def get_content(context, author: str, permlink: str, observer=None):
    db = context['db']
    return await _get_content_impl(db, True, author, permlink, observer)

@return_error_info
async def _get_content_impl(db, fat_node_style, author: str, permlink: str, observer=None):
    """Get a single post object."""
    valid_account(author)
    valid_permlink(permlink)

    sql = "SELECT * FROM condenser_get_content(:author, :permlink)"

    post = None
    result = await db.query_all(sql, author=author, permlink=permlink)
    if result:
        result = dict(result[0])
        post = _condenser_post_object(result, 0, fat_node_style)
        post['active_votes'] = await find_votes_impl(db, author, permlink, VotesPresentation.ActiveVotes if fat_node_style else VotesPresentation.CondenserApi)
        if not observer:
            post['active_votes'] = _mute_votes(post['active_votes'], Mutes.all())
        else:
            blacklists_for_user = await Mutes.get_blacklists_for_observer(observer, context)
            post['active_votes'] = _mute_votes(post['active_votes'], blacklists_for_user.keys())

    return post

@return_error_info
async def get_content_replies(context, author: str, permlink: str):
    db = context['db']
    return await _get_content_replies_impl(db, True, author, permlink)

@return_error_info
async def _get_content_replies_impl(db, fat_node_style, author: str, permlink: str):
    """Get a list of post objects based on parent."""
    valid_account(author)
    valid_permlink(permlink)

    sql = "SELECT * FROM condenser_get_content_replies(:author, :permlink)"
    result = await db.query_all(sql, author=author, permlink=permlink)

    muted_accounts = Mutes.all()

    posts = []
    for row in result:
        row = dict(row)
        post = _condenser_post_object(row, get_content_additions=fat_node_style)
        post['active_votes'] = await find_votes_impl(db, row['author'], row['permlink'], VotesPresentation.ActiveVotes if fat_node_style else VotesPresentation.CondenserApi)
        post['active_votes'] = _mute_votes(post['active_votes'], muted_accounts)
        posts.append(post)

    return posts

# Discussion Queries

def nested_query_compat(function):
    """Unpack strange format used by some clients, accepted by steemd.

    Sometimes a discussion query object is nested inside a list[1]. Eg:

        {... "method":"condenser_api.get_discussions_by_hot",
             "params":[{"tag":"steem","limit":1}]}

    In these cases jsonrpcserver dispatch just shoves it into the first
    arg. This decorator checks for this specific condition and unpacks
    the query to be passed as kwargs.
    """
    @wraps(function)
    def wrapper(*args, **kwargs):
        """Checks for specific condition signature and unpacks query"""
        if args and not kwargs and len(args) == 2 and isinstance(args[1], dict):
            return function(args[0], **args[1])
        return function(*args, **kwargs)
    return wrapper

@return_error_info
@nested_query_compat
async def get_posts_by_given_sort(context, sort: str, start_author: str = '', start_permlink: str = '',
                                     limit: int = 20, tag: str = None,
                                     truncate_body: int = 0, filter_tags: list = None):
    """Query posts, sorted by creation date."""
    assert not filter_tags, 'filter_tags not supported'

    db = context['db']

    start_author    = valid_account(start_author, allow_empty=True),
    start_permlink  = valid_permlink(start_permlink, allow_empty=True),
    limit           = valid_limit(limit, 100, 20),
    tag             = valid_tag(tag, allow_empty=True)

    posts = []
   
    if sort == 'created':
      sql = "SELECT * FROM condenser_get_discussions_by_created( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
    elif sort == 'trending':
      sql = "SELECT * FROM condenser_get_discussions_by_trending( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
    elif sort == 'hot':
      sql = "SELECT * FROM condenser_get_discussions_by_hot( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
    elif sort == 'promoted':
      sql = "SELECT * FROM condenser_get_discussions_by_promoted( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
    elif sort == 'post_by_payout':
      sql = "SELECT * FROM condenser_get_post_discussions_by_payout( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
    elif sort == 'comment_by_payout':
      sql = "SELECT * FROM condenser_get_comment_discussions_by_payout( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
    else:
      return posts

    sql_result = await db.query_all(sql, tag=tag, author=start_author, permlink=start_permlink, limit=limit )

    for row in sql_result:
        post = _condenser_post_object(row, truncate_body)
        post['active_votes'] = await find_votes_impl(db, row['author'], row['permlink'], VotesPresentation.CondenserApi)
        posts.append(post)
    return posts

@return_error_info
@nested_query_compat
async def get_discussions_by_created(context, start_author: str = '', start_permlink: str = '',
                                     limit: int = 20, tag: str = None,
                                     truncate_body: int = 0, filter_tags: list = None):
  return await get_posts_by_given_sort(context, 'created', start_author, start_permlink, limit, tag, truncate_body, filter_tags)

@return_error_info
@nested_query_compat
async def get_discussions_by_trending(context, start_author: str = '', start_permlink: str = '',
                                      limit: int = 20, tag: str = None,
                                      truncate_body: int = 0, filter_tags: list = None):
  return await get_posts_by_given_sort(context, 'trending', start_author, start_permlink, limit, tag, truncate_body, filter_tags)

@return_error_info
@nested_query_compat
async def get_discussions_by_hot(context, start_author: str = '', start_permlink: str = '',
                                 limit: int = 20, tag: str = None,
                                 truncate_body: int = 0, filter_tags: list = None):
  return await get_posts_by_given_sort(context, 'hot', start_author, start_permlink, limit, tag, truncate_body, filter_tags)

@return_error_info
@nested_query_compat
async def get_discussions_by_promoted(context, start_author: str = '', start_permlink: str = '',
                                      limit: int = 20, tag: str = None,
                                      truncate_body: int = 0, filter_tags: list = None):
  return await get_posts_by_given_sort(context, 'promoted', start_author, start_permlink, limit, tag, truncate_body, filter_tags)

@return_error_info
@nested_query_compat
async def get_post_discussions_by_payout(context, start_author: str = '', start_permlink: str = '',
                                         limit: int = 20, tag: str = None,
                                         truncate_body: int = 0):
  return await get_posts_by_given_sort(context, 'post_by_payout', start_author, start_permlink, limit, tag, truncate_body, [])

@return_error_info
@nested_query_compat
async def get_comment_discussions_by_payout(context, start_author: str = '', start_permlink: str = '',
                                            limit: int = 20, tag: str = None,
                                            truncate_body: int = 0):
  return await get_posts_by_given_sort(context, 'comment_by_payout', start_author, start_permlink, limit, tag, truncate_body, [])

@return_error_info
@nested_query_compat
async def get_discussions_by_blog(context, tag: str = None, start_author: str = '',
                                  start_permlink: str = '', limit: int = 20,
                                  truncate_body: int = 0, filter_tags: list = None):
    """Retrieve account's blog posts, including reblogs."""
    assert tag, '`tag` cannot be blank'
    assert not filter_tags, 'filter_tags not supported'
    valid_account(tag)
    valid_account(start_author, allow_empty=True)
    valid_permlink(start_permlink, allow_empty=True)
    valid_limit(limit, 100, 20)

    sql = """
        SELECT * FROM get_discussions_by_blog(:author, :start_author, :start_permlink, :limit)
    """

    db = context['db']
    result = await db.query_all(sql, author=tag, start_author=start_author, start_permlink=start_permlink, limit=limit)
    posts_by_id = []

    for row in result:
        row = dict(row)
        post = _condenser_post_object(row, truncate_body=truncate_body)
        post['active_votes'] = await find_votes_impl(db, post['author'], post['permlink'], VotesPresentation.CondenserApi)
        post['active_votes'] = _mute_votes(post['active_votes'], Mutes.all())
        #posts_by_id[row['post_id']] = post
        posts_by_id.append(post)

    return posts_by_id

@return_error_info
@nested_query_compat
async def get_discussions_by_feed(context, tag: str = None, start_author: str = '',
                                  start_permlink: str = '', limit: int = 20,
                                  truncate_body: int = 0, filter_tags: list = None):
    """Retrieve account's personalized feed."""
    assert tag, '`tag` cannot be blank'
    assert not filter_tags, 'filter_tags not supported'
    res = await cursor.pids_by_feed_with_reblog(
        context['db'],
        valid_account(tag),
        valid_account(start_author, allow_empty=True),
        valid_permlink(start_permlink, allow_empty=True),
        valid_limit(limit, 100, 20))
    return await load_posts_reblogs(context['db'], res, truncate_body=truncate_body)


@return_error_info
@nested_query_compat
async def get_discussions_by_comments(context, start_author: str = None, start_permlink: str = '',
                                      limit: int = 20, truncate_body: int = 0,
                                      filter_tags: list = None):
    """Get comments by made by author."""
    assert start_author, '`start_author` cannot be blank'
    assert not filter_tags, 'filter_tags not supported'
    valid_account(start_author)
    valid_permlink(start_permlink, allow_empty=True)
    valid_limit(limit, 100, 20)

    #force copy
    sql = str(SQL_TEMPLATE)
    sql += """
        WHERE
            hp.author = :start_author AND hp.depth > 0
    """

    if start_permlink:
        sql += """
            AND hp.id <= (SELECT hive_posts.id FROM  hive_posts WHERE author_id = (SELECT id FROM hive_accounts WHERE name = :start_author) AND permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :start_permlink))
        """

    sql += """
        ORDER BY hp.id DESC, hp.depth LIMIT :limit
    """

    posts = []
    db = context['db']
    result = await db.query_all(sql, start_author=start_author, start_permlink=start_permlink, limit=limit)

    for row in result:
        row = dict(row)
        post = _condenser_post_object(row, truncate_body=truncate_body)
        post['active_votes'] = await find_votes_impl(db, post['author'], post['permlink'], VotesPresentation.CondenserApi)
        post['active_votes'] = _mute_votes(post['active_votes'], Mutes.all())
        posts.append(post)

    return posts

@return_error_info
@nested_query_compat
async def get_replies_by_last_update(context, start_author: str = None, start_permlink: str = '',
                                     limit: int = 20, truncate_body: int = 0):
    """Get all replies made to any of author's posts."""
    assert start_author, '`start_author` cannot be blank'

    ids = await cursor.pids_by_replies_to_account(
        context['db'],
        valid_account(start_author),
        valid_permlink(start_permlink, allow_empty=True),
        valid_limit(limit, 100, 20))
    return await load_posts(context['db'], ids, truncate_body=truncate_body)


@return_error_info
@nested_query_compat
async def get_discussions_by_author_before_date(context, author: str = None, start_permlink: str = '',
                                                before_date: str = '', limit: int = 10):
    """Retrieve account's blog posts, without reblogs.

    NOTE: before_date is completely ignored, and it appears to be broken and/or
    completely ignored in steemd as well. This call is similar to
    get_discussions_by_blog but does NOT serve reblogs.
    """
    # pylint: disable=invalid-name,unused-argument
    assert author, '`author` cannot be blank'
    ids = await cursor.pids_by_blog_without_reblog(
        context['db'],
        valid_account(author),
        valid_permlink(start_permlink, allow_empty=True),
        valid_limit(limit, 100, 10))
    return await load_posts(context['db'], ids)

@return_error_info
@nested_query_compat
async def get_blog(context, account: str, start_entry_id: int = 0, limit: int = None):
    """Get posts for an author's blog (w/ reblogs), paged by index/limit.

    Equivalent to get_discussions_by_blog, but uses offset-based pagination.
    """
    return await _get_blog(context['db'], account, start_entry_id, limit)

@return_error_info
@nested_query_compat
async def get_blog_entries(context, account: str, start_entry_id: int = 0, limit: int = None):
    """Get 'entries' for an author's blog (w/ reblogs), paged by index/limit.

    Interface identical to get_blog, but returns minimalistic post references.
    """

    entries = await _get_blog(context['db'], account, start_entry_id, limit)
    for entry in entries:
        # replace the comment body with just author/permlink
        post = entry.pop('comment')
        entry['author'] = post['author']
        entry['permlink'] = post['permlink']

    return entries

async def _get_blog(db, account: str, start_index: int, limit: int = None):
    """Get posts for an author's blog (w/ reblogs), paged by index/limit.

    Examples:
    (acct, 2) = returns blog entries 0 up to 2 (3 oldest)
    (acct, 0) = returns all blog entries (limit 0 means return all?)
    (acct, 2, 1) = returns 1 post starting at idx 2
    (acct, 2, 3) = returns 3 posts: idxs (2,1,0)
    (acct, -1, 10) = returns latest 10 posts
    """

    if start_index is None:
        start_index = 0

    if not limit:
        limit = start_index + 1

    start_index, ids = await cursor.pids_by_blog_by_index(
        db,
        valid_account(account),
        valid_offset(start_index),
        valid_limit(limit, 500, None))

    out = []

    idx = int(start_index)
    for post in await load_posts(db, ids):
        reblog = post['author'] != account
        reblog_on = post['created'] if reblog else "1970-01-01T00:00:00"

        out.append({"blog": account,
                    "entry_id": idx,
                    "comment": post,
                    "reblogged_on": reblog_on})
        idx -= 1

    return out

@return_error_info
async def get_active_votes(context, author: str, permlink: str):
    """ Returns all votes for the given post. """
    valid_account(author)
    valid_permlink(permlink)
    db = context['db']

    return await find_votes_impl( db, author, permlink, VotesPresentation.ActiveVotes  )
