"""Steemd/condenser_api compatibility layer API methods."""
from json import loads
from functools import wraps

import hive.server.condenser_api.cursor as cursor
from hive.server.condenser_api.objects import load_posts, load_posts_reblogs, resultset_to_posts
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
from hive.server.database_api.methods import find_votes
from hive.utils.normalize import rep_to_raw, number_to_json_value, time_string_with_t

# pylint: disable=too-many-arguments,line-too-long,too-many-lines

SQL_TEMPLATE = """
    SELECT
        hp.id,
        hp.community_id,
        hp.author,
        hp.permlink,
        hp.author_rep,
        hp.title,
        hp.body,
        hp.category,
        hp.depth,
        hp.promoted,
        hp.payout,
        hp.payout_at,
        hp.is_paidout,
        hp.children,
        hp.votes,
        hp.active_votes,
        hp.created_at,
        hp.updated_at,
        hp.rshares,
        hp.json,
        hp.is_hidden,
        hp.is_grayed,
        hp.total_votes,
        hp.flag_weight,
        hp.parent_author,
        hp.parent_permlink,
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
        hp.root_title
    FROM vw_hive_posts hp
    WHERE
"""

@return_error_info
async def get_account_votes(context, account):
    """Return an info message about get_acccount_votes being unsupported."""
    # pylint: disable=unused-argument
    raise ApiError("get_account_votes is no longer supported, for details see "
                   "https://steemit.com/steemit/@steemitdev/additional-public-api-change")


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
        valid_limit(limit, 1000))
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
        valid_limit(limit, 1000))
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
    """List account reputations"""
    return {'reputations': await cursor.get_account_reputations(
        context['db'],
        account_lower_bound,
        valid_limit(limit, 1000))}


# Content Primitives

@return_error_info
async def get_content(context, author: str, permlink: str, observer=None):
    """Get a single post object."""
    db = context['db']
    valid_account(author)
    valid_permlink(permlink)
    #force copy
    sql = str(SQL_TEMPLATE)
    sql += """ hp.author = :author AND hp.permlink = :permlink AND NOT hp.is_deleted """

    post = None
    result = await db.query_all(sql, author=author, permlink=permlink)
    if result:
        result = dict(result[0])
        post = _condenser_post_object(result, 0)
        post['active_votes'] = await find_votes(context, {'author':author, 'permlink':permlink})
        if not observer:
            post['active_votes'] = _mute_votes(post['active_votes'], Mutes.all())
        else:
            blacklists_for_user = await Mutes.get_blacklists_for_observer(observer, context)
            post['active_votes'] = _mute_votes(post['active_votes'], blacklists_for_user.keys())

    assert post, 'post was not found in cache'
    return post

@return_error_info
async def get_content_replies(context, author: str, permlink: str):
    """Get a list of post objects based on parent."""
    db = context['db']
    valid_account(author)
    valid_permlink(permlink)

    #force copy
    sql = str(SQL_TEMPLATE)
    sql += """
            hp.is_deleted = '0' AND hp.parent_author = :author AND hp.parent_permlink = :permlink
        ORDER BY hp.id LIMIT :limit
    """

    result = await db.query_all(sql, author=author, permlink=permlink, limit=5000)

    posts = await resultset_to_posts(db=db, resultset=result, truncate_body=0)
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
async def get_discussions_by(discussion_type, context, start_author: str = '',
                             start_permlink: str = '', limit: int = 20,
                             tag: str = None, truncate_body: int = 0,
                             filter_tags: list = None):
    """ Common implementation for get_discussions_by calls  """
    assert not filter_tags, 'filter tags not supported'
    assert discussion_type in ['trending', 'hot', 'created', 'promoted',
                               'payout', 'payout_comments'], 'invalid discussion type'
    valid_account(start_author, allow_empty=True)
    valid_permlink(start_permlink, allow_empty=True)
    valid_limit(limit, 100)
    valid_tag(tag, allow_empty=True)
    db = context['db']

    sql = "---get_discussions_by_" + discussion_type + "\r\n" + str(SQL_TEMPLATE)

    sql = sql + """ NOT hp.is_deleted """

    if discussion_type == 'trending':
        sql = sql + """ AND NOT hp.is_paidout %s ORDER BY hp.sc_trend DESC LIMIT :limit """
    elif discussion_type == 'hot':
        sql = sql + """ AND NOT hp.is_paidout %s ORDER BY hp.sc_hot DESC LIMIT :limit """
    elif discussion_type == 'created':
        sql = sql + """ AND hp.depth = 0 %s ORDER BY hp.created_at DESC LIMIT :limit """
    elif discussion_type == 'promoted':
        sql = sql + """ AND NOT hp.is_paidout AND hp.promoted > 0
                        %s ORDER BY hp.promoted DESC LIMIT :limit """
    elif discussion_type == 'payout':
        sql = sql + """ AND NOT hp.is_paidout AND hp.depth = 0
                        %s ORDER BY hp.payout DESC LIMIT :limit """
    elif discussion_type == 'payout_comments':
        sql = sql + """ AND NOT hp.is_paidout AND hp.depth > 0
                        %s ORDER BY hp.payout DESC LIMIT :limit """

    if tag and tag != 'all':
        if tag[:5] == 'hive-':
            sql = sql % """ %s AND hp.category = :tag """
        else:
            sql = sql % """ %s AND EXISTS
                (SELECT NULL
                    FROM hive_post_tags hpt
                    INNER JOIN hive_tag_data htd ON hpt.tag_id=htd.id
                    WHERE hp.id = hpt.post_id AND htd.tag = :tag
                ) """

    if start_author and start_permlink:
        if discussion_type == 'trending':
            sql = sql % """ AND hp.sc_trend <= (SELECT sc_trend FROM hp WHERE permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :permlink) AND author_id = (SELECT id FROM hive_accounts WHERE name = :author))
                            AND hp.post_id != (SELECT post_id FROM hp WHERE permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :permlink) AND author_id = (SELECT id FROM hive_accounts WHERE name = :author)) """
        elif discussion_type == 'hot':
            sql = sql % """ AND hp.sc_hot <= (SELECT sc_hot FROM hp WHERE permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :permlink) AND author_id = (SELECT id FROM hive_accounts WHERE name = :author))
                            AND hp.post_id != (SELECT post_id FROM hp WHERE permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :permlink) AND author_id = (SELECT id FROM hive_accounts WHERE name = :author)) """
        elif discussion_type == 'created':
            sql = sql % """ AND hp.post_id < (SELECT post_id FROM hp WHERE permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :permlink) AND author_id = (SELECT id FROM hive_accounts WHERE name = :author)) """
        elif discussion_type == 'promoted':
            sql = sql % """ AND hp.promoted <= (SELECT promoted FROM hp WHERE permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :permlink) AND author_id = (SELECT id FROM hive_accounts WHERE name = :author))
                            AND hp.post_id != (SELECT post_id FROM hp WHERE permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :permlink) AND author_id = (SELECT id FROM hive_accounts WHERE name = :author)) """
        else:
            sql = sql % """ AND hp.payout <= (SELECT payout FROM hp where permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :permlink) AND author_id = (SELECT id FROM hive_accounts WHERE name = :author))
                            AND hp.post_id != (SELECT post_id FROM hp WHERE permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :permlink) AND author_id = (SELECT id FROM hive_accounts WHERE name = :author)) """
    else:
        sql = sql % """ """

    result = await db.query_all(sql, tag=tag, limit=limit, author=start_author, permlink=start_permlink)
    posts = []
    for row in result:
        post = _condenser_post_object(row, truncate_body)
        post['active_votes'] = await find_votes(context, {'author':post['author'], 'permlink':post['permlink']})
        post['active_votes'] = _mute_votes(post['active_votes'], Mutes.all())
        posts.append(post)
    #posts = await resultset_to_posts(db=db, resultset=result, truncate_body=truncate_body)
    return posts

@return_error_info
@nested_query_compat
async def get_discussions_by_trending(context, start_author: str = '', start_permlink: str = '',
                                      limit: int = 20, tag: str = None,
                                      truncate_body: int = 0, filter_tags: list = None):
    """Query posts, sorted by trending score."""
    assert not filter_tags, 'filter_tags not supported'
    ids = await cursor.pids_by_query(
        context['db'],
        'trending',
        valid_account(start_author, allow_empty=True),
        valid_permlink(start_permlink, allow_empty=True),
        valid_limit(limit, 100),
        valid_tag(tag, allow_empty=True))
    return await load_posts(context['db'], ids, truncate_body=truncate_body)


@return_error_info
@nested_query_compat
async def get_discussions_by_hot(context, start_author: str = '', start_permlink: str = '',
                                 limit: int = 20, tag: str = None,
                                 truncate_body: int = 0, filter_tags: list = None):
    """Query posts, sorted by hot score."""
    assert not filter_tags, 'filter_tags not supported'
    ids = await cursor.pids_by_query(
        context['db'],
        'hot',
        valid_account(start_author, allow_empty=True),
        valid_permlink(start_permlink, allow_empty=True),
        valid_limit(limit, 100),
        valid_tag(tag, allow_empty=True))
    return await load_posts(context['db'], ids, truncate_body=truncate_body)


@return_error_info
@nested_query_compat
async def get_discussions_by_promoted(context, start_author: str = '', start_permlink: str = '',
                                      limit: int = 20, tag: str = None,
                                      truncate_body: int = 0, filter_tags: list = None):
    """Query posts, sorted by promoted amount."""
    assert not filter_tags, 'filter_tags not supported'
    ids = await cursor.pids_by_query(
        context['db'],
        'promoted',
        valid_account(start_author, allow_empty=True),
        valid_permlink(start_permlink, allow_empty=True),
        valid_limit(limit, 100),
        valid_tag(tag, allow_empty=True))
    return await load_posts(context['db'], ids, truncate_body=truncate_body)


@return_error_info
@nested_query_compat
async def get_discussions_by_created(context, start_author: str = '', start_permlink: str = '',
                                     limit: int = 20, tag: str = None,
                                     truncate_body: int = 0, filter_tags: list = None):
    """Query posts, sorted by creation date."""
    assert not filter_tags, 'filter_tags not supported'
    ids = await cursor.pids_by_query(
        context['db'],
        'created',
        valid_account(start_author, allow_empty=True),
        valid_permlink(start_permlink, allow_empty=True),
        valid_limit(limit, 100),
        valid_tag(tag, allow_empty=True))
    return await load_posts(context['db'], ids, truncate_body=truncate_body)


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
    valid_limit(limit, 100)

    #force copy
    sql = str(SQL_TEMPLATE)
    sql += """
            NOT hp.is_deleted AND hp.id IN
                (SELECT post_id FROM hive_feed_cache JOIN hive_accounts ON (hive_feed_cache.account_id = hive_accounts.id) WHERE hive_accounts.name = :author)
          """
    if start_author and start_permlink != '':
        sql += """
         AND hp.created_at <= (SELECT created_at from hive_posts WHERE author_id = (SELECT id FROM hive_accounts WHERE name = :start_author) AND permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :start_permlink))
        """

    sql += """
        ORDER BY hp.created_at DESC
        LIMIT :limit
    """

    db = context['db']
    result = await db.query_all(sql, author=tag, start_author=start_author, start_permlink=start_permlink, limit=limit)
    posts_by_id = []

    for row in result:
        row = dict(row)
        post = _condenser_post_object(row, truncate_body=truncate_body)
        post['active_votes'] = await find_votes(context, {'author':post['author'], 'permlink':post['permlink']})
        post['active_votes'] = _mute_votes(post['active_votes'], Mutes.all())
        #posts_by_id[row['post_id']] = post
        posts_by_id.append(post)

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
        valid_limit(limit, 100))
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
    valid_limit(limit, 100)

    #force copy
    sql = str(SQL_TEMPLATE)
    sql += """
            hp.author = :start_author AND hp.depth > 0
            AND NOT hp.is_deleted
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
        post['active_votes'] = await find_votes(context, {'author':post['author'], 'permlink':post['permlink']})
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
        valid_limit(limit, 100))
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
        valid_limit(limit, 100))
    return await load_posts(context['db'], ids)


@return_error_info
@nested_query_compat
async def get_post_discussions_by_payout(context, start_author: str = '', start_permlink: str = '',
                                         limit: int = 20, tag: str = None,
                                         truncate_body: int = 0):
    """Query top-level posts, sorted by payout."""
    ids = await cursor.pids_by_query(
        context['db'],
        'payout',
        valid_account(start_author, allow_empty=True),
        valid_permlink(start_permlink, allow_empty=True),
        valid_limit(limit, 100),
        valid_tag(tag, allow_empty=True))
    return await load_posts(context['db'], ids, truncate_body=truncate_body)


@return_error_info
@nested_query_compat
async def get_comment_discussions_by_payout(context, start_author: str = '', start_permlink: str = '',
                                            limit: int = 20, tag: str = None,
                                            truncate_body: int = 0):
    """Query comments, sorted by payout."""
    # pylint: disable=invalid-name
    ids = await cursor.pids_by_query(
        context['db'],
        'payout_comments',
        valid_account(start_author, allow_empty=True),
        valid_permlink(start_permlink, allow_empty=True),
        valid_limit(limit, 100),
        valid_tag(tag, allow_empty=True))
    return await load_posts(context['db'], ids, truncate_body=truncate_body)


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
        valid_limit(limit, 500))

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
async def get_accounts(context, accounts: list):
    """Returns accounts data for accounts given in list"""
    assert accounts, "Empty parameters are not supported"
    assert len(accounts) < 1000, "Query exceeds limit"

    return await cursor.get_accounts(context['db'], accounts)

@return_error_info
async def get_active_votes(context, author: str, permlink: str):
    """ Returns all votes for the given post. """
    valid_account(author)
    valid_permlink(permlink)
    db = context['db']
    sql = """
        SELECT
            percent,
            reputation,
            rshares,
            time,
            voter,
            weight
        FROM
            wv_hive_votes_accounts_permlinks
        WHERE author = :author AND permlink = :permlink
        ORDER BY id
    """
    ret = []
    rows = await db.query_all(sql, author=author, permlink=permlink)
    for row in rows:
        ret.append(dict(percent=row.percent, reputation=rep_to_raw(row.reputation),
                        rshares=number_to_json_value(row.rshares), time=time_string_with_t(row.time), voter=row.voter,
                        weight=number_to_json_value(row.weight),
                        ))
    return ret
