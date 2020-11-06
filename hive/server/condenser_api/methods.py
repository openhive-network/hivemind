"""Steemd/condenser_api compatibility layer API methods."""
from functools import wraps

import hive.server.condenser_api.cursor as cursor
from hive.server.condenser_api.objects import _mute_votes, _condenser_post_object
from hive.server.common.helpers import (
    ApiError,
    return_error_info,
    json_date,
    valid_account,
    valid_permlink,
    valid_tag,
    valid_offset,
    valid_limit,
    valid_follow_type)
from hive.server.common.mutes import Mutes
from hive.server.database_api.methods import find_votes_impl, VotesPresentation

# pylint: disable=too-many-arguments,line-too-long,too-many-lines

@return_error_info
async def get_account_votes(context, account):
    """Return an info message about get_acccount_votes being unsupported."""
    # pylint: disable=unused-argument
    assert False, "get_account_votes is no longer supported, for details see https://hive.blog/steemit/@steemitdev/additional-public-api-change"


# Follows Queries

def _legacy_follower(follower, following, follow_type):
    return dict(follower=follower, following=following, what=[follow_type])

@return_error_info
async def get_followers(context, account: str, start: str = '', follow_type: str = None,
                        limit: int = 1000, **kwargs):
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
        valid_limit(limit, 1000, 1000))
    return [_legacy_follower(name, account, follow_type) for name in followers]

@return_error_info
async def get_following(context, account: str, start: str = '', follow_type: str = None,
                        limit: int = 1000, **kwargs):
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
        valid_limit(limit, 1000, 1000))
    return [_legacy_follower(account, name, follow_type) for name in following]

@return_error_info
async def get_follow_count(context, account: str):
    """Get follow count stats. (EOL)"""
    db = context['db']
    account = valid_account(account)
    sql = "SELECT * FROM condenser_get_follow_count( (:account)::VARCHAR )"
    counters = await db.query_row(sql, account=account)
    return dict(account=account,
                following_count=counters[0],
                follower_count=counters[1])

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
    assert isinstance(account_lower_bound, str), "invalid account_lower_bound type"
    limit = valid_limit(limit, 1000, 1000)

    sql = "SELECT * FROM condenser_get_account_reputations( '{}', {}, {} )".format( account_lower_bound, account_lower_bound is None, limit )
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
            blacklists_for_user = await Mutes.get_blacklists_for_observer(observer, {'db':db})
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
    is_community = tag[:5] == 'hive-'
   
    if sort == 'created':
      if is_community:
        sql = "SELECT * FROM bridge_get_ranked_post_by_created_for_community( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, False )"
      elif tag == '':
        sql = "SELECT * FROM bridge_get_ranked_post_by_created( (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
      else:
        sql = "SELECT * FROM bridge_get_ranked_post_by_created_for_tag( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
    elif sort == 'trending':
      if is_community:
        sql = "SELECT * FROM bridge_get_ranked_post_by_trends_for_community( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, False )"
      elif tag == '':
        sql = "SELECT * FROM bridge_get_ranked_post_by_trends( (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
      else:
        sql = "SELECT * FROM bridge_get_ranked_post_by_trends_for_tag( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
    elif sort == 'hot':
      if is_community:
        sql = "SELECT * FROM bridge_get_ranked_post_by_hot_for_community( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
      elif tag == '':
        sql = "SELECT * FROM bridge_get_ranked_post_by_hot( (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
      else:
        sql = "SELECT * FROM bridge_get_ranked_post_by_hot_for_tag( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
    elif sort == 'promoted':
      if is_community:
        sql = "SELECT * FROM bridge_get_ranked_post_by_promoted_for_community( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
      elif tag == '':
        sql = "SELECT * FROM bridge_get_ranked_post_by_promoted( (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
      else:
        sql = "SELECT * FROM bridge_get_ranked_post_by_promoted_for_tag( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
    elif sort == 'post_by_payout':
      if tag == '':
        sql = "SELECT * FROM bridge_get_ranked_post_by_payout( (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, False )"
      else:
        sql = "SELECT * FROM bridge_get_ranked_post_by_payout_for_category( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, False )"
    elif sort == 'comment_by_payout':
      if tag == '':
        sql = "SELECT * FROM bridge_get_ranked_post_by_payout_comments( (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
      else:
        sql = "SELECT * FROM bridge_get_ranked_post_by_payout_comments_for_category( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
    else:
      return posts

    sql_result = await db.query_all(sql, tag=tag, author=start_author, permlink=start_permlink, limit=limit )

    muted_accounts = Mutes.all()
    for row in sql_result:
        post = _condenser_post_object(row, truncate_body)
        post['active_votes'] = await find_votes_impl(db, row['author'], row['permlink'], VotesPresentation.CondenserApi)
        post['active_votes'] = _mute_votes(post['active_votes'], muted_accounts)
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

async def get_discussions_by_feed_impl(db, account: str, start_author: str = '',
                                   start_permlink: str = '', limit: int = 20, truncate_body: int = 0):
    """Get a list of posts for an account's feed."""
    sql = "SELECT * FROM bridge_get_by_feed_with_reblog((:account)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::INTEGER)"
    result = await db.query_all(sql, account=account, author=start_author, permlink=start_permlink, limit=limit)

    posts = []
    for row in result:
        row = dict(row)
        post = _condenser_post_object(row, truncate_body=truncate_body)
        reblogged_by = set(row['reblogged_by'])
        reblogged_by.discard(row['author']) # Eliminate original author of reblogged post
        if reblogged_by:
            reblogged_by_list = list(reblogged_by)
            reblogged_by_list.sort()
            post['reblogged_by'] = reblogged_by_list

        post['active_votes'] = await find_votes_impl(db, row['author'], row['permlink'], VotesPresentation.CondenserApi)
        posts.append(post)

    return posts


@return_error_info
@nested_query_compat
async def get_discussions_by_feed(context, tag: str = None, start_author: str = '',
                                  start_permlink: str = '', limit: int = 20,
                                  truncate_body: int = 0, filter_tags: list = None):
    """Retrieve account's personalized feed."""
    assert tag, '`tag` cannot be blank'
    assert not filter_tags, 'filter_tags not supported'
    return await get_discussions_by_feed_impl(
        context['db'],
        valid_account(tag),
        valid_account(start_author, allow_empty=True),
        valid_permlink(start_permlink, allow_empty=True),
        valid_limit(limit, 100, 20),
        truncate_body)

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

    posts = []
    db = context['db']

    sql = " SELECT * FROM condenser_get_discussions_by_comments( '{}', '{}', {} ) ".format( start_author, start_permlink, limit )
    result = await db.query_all(sql)

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

    return await cursor.get_by_replies_to_account(
        context['db'],
        valid_account(start_author),
        valid_permlink(start_permlink, allow_empty=True),
        valid_limit(limit, 100, 20),
        truncate_body)

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
    return await cursor.get_by_blog_without_reblog(
        context['db'],
        valid_account(author),
        valid_permlink(start_permlink, allow_empty=True),
        valid_limit(limit, 100, 10))

@return_error_info
@nested_query_compat
async def get_blog(context, account: str, start_entry_id: int = 0, limit: int = None):
    """Get posts for an author's blog (w/ reblogs), paged by index/limit.

    Equivalent to get_discussions_by_blog, but uses offset-based pagination.

    Examples: (ABW: old description and examples were misleading as in many cases code worked differently, also now more cases actually work that gave error earlier)
    (acct, -1, limit) for limit 1..500 - returns latest (no more than) limit posts
    (acct, 0) - returns latest single post (ABW: this is a bug but I left it here because I'm afraid it was actively used - it should return oldest post)
    (acct, 0, limit) for limit 1..500 - same as (acct, -1, limit) - see above
    (acct, last_idx) for positive last_idx - returns last_idx oldest posts, or posts in range [last_idx..last_idx-500) when last_idx >= 500
    (acct, last_idx, limit) for positive last_idx and limit 1..500 - returns posts in range [last_idx..last_idx-limit)
    """
    db = context['db']

    account = valid_account(account)
    if not start_entry_id:
        start_entry_id = -1
    start_entry_id = valid_offset(start_entry_id)
    if not limit:
        limit = max(start_entry_id + 1, 1)
        limit = min(limit, 500)
    limit = valid_limit(limit, 500, None)

    sql = "SELECT * FROM condenser_get_blog(:account, :last, :limit)"
    result = await db.query_all(sql, account=account, last=start_entry_id, limit=limit)

    muted_accounts = Mutes.all()
    out = []
    for row in result:
        row = dict(row)
        post = _condenser_post_object(row)

        post['active_votes'] = await find_votes_impl(db, row['author'], row['permlink'], VotesPresentation.CondenserApi)
        post['active_votes'] = _mute_votes(post['active_votes'], muted_accounts)

        out.append({"blog": account,
                    "entry_id": row['entry_id'],
                    "comment": post,
                    "reblogged_on": json_date(row['reblogged_at'])})

    return list(reversed(out))

@return_error_info
@nested_query_compat
async def get_blog_entries(context, account: str, start_entry_id: int = 0, limit: int = None):
    """Get 'entries' for an author's blog (w/ reblogs), paged by index/limit.

    Interface identical to get_blog, but returns minimalistic post references.
    """
    db = context['db']

    account = valid_account(account)
    if not start_entry_id:
        start_entry_id = -1
    start_entry_id = valid_offset(start_entry_id)
    if not limit:
        limit = max(start_entry_id + 1, 1)
        limit = min(limit, 500)
    limit = valid_limit(limit, 500, None)

    sql = "SELECT * FROM condenser_get_blog_entries(:account, :last, :limit)"
    result = await db.query_all(sql, account=account, last=start_entry_id, limit=limit)

    out = []
    for row in result:
        row = dict(row)
        out.append({"blog": account,
                    "entry_id": row['entry_id'],
                    "author": row['author'],
                    "permlink": row['permlink'],
                    "reblogged_on": json_date(row['reblogged_at'])})

    return list(reversed(out))

@return_error_info
async def get_active_votes(context, author: str, permlink: str):
    """ Returns all votes for the given post. """
    valid_account(author)
    valid_permlink(permlink)
    db = context['db']

    return await find_votes_impl( db, author, permlink, VotesPresentation.ActiveVotes  )
