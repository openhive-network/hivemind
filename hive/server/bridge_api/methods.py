"""Bridge API public endpoints for posts"""

import hive.server.bridge_api.cursor as cursor
from hive.server.bridge_api.objects import load_posts, load_posts_reblogs, load_profiles, _bridge_post_object
from hive.server.database_api.methods import find_votes_impl, VotesPresentation
from hive.server.common.helpers import (
    return_error_info,
    valid_account,
    valid_permlink,
    valid_tag,
    valid_limit)
from hive.server.hive_api.common import get_account_id
from hive.server.hive_api.objects import _follow_contexts
from hive.server.hive_api.community import list_top_communities
from hive.server.common.mutes import Mutes


ROLES = {-2: 'muted', 0: 'guest', 2: 'member', 4: 'mod', 6: 'admin', 8: 'owner'}

SQL_TEMPLATE = """
        SELECT
            hp.id,
            hp.author,
            hp.parent_author,
            hp.author_rep,
            hp.root_title,
            hp.beneficiaries,
            hp.max_accepted_payout,
            hp.percent_hbd,
            hp.url,
            hp.permlink,
            hp.parent_permlink_or_category,
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
            hp.sc_trend,
            hp.role_title,
            hp.community_title,
            hp.role_id,
            hp.is_pinned,
            hp.curator_payout_value
        FROM hive_posts_view hp
        WHERE
    """

#pylint: disable=too-many-arguments, no-else-return

@return_error_info
async def get_profile(context, account, observer=None):
    """Load account/profile data."""
    db = context['db']
    ret = await load_profiles(db, [valid_account(account)])
    assert ret, 'Account \'{}\' does not exist'.format(account)

    observer_id = await get_account_id(db, observer) if observer else None
    if observer_id:
        await _follow_contexts(db, {ret[0]['id']: ret[0]}, observer_id, True)
    return ret[0]

@return_error_info
async def get_trending_topics(context, limit:int=10, observer:str=None):
    """Return top trending topics across pending posts."""
    # pylint: disable=unused-argument
    #db = context['db']
    #observer_id = await get_account_id(db, observer) if observer else None
    #assert not observer, 'observer not supported'
    limit = valid_limit(limit, 25, 10)
    out = []
    cells = await list_top_communities(context, limit)
    for name, title in cells:
        out.append((name, title or name))
    for tag in ('photography', 'travel', 'gaming',
                'crypto', 'newsteem', 'music', 'food'):
        if len(out) < limit:
            out.append((tag, '#' + tag))
    return out

@return_error_info
async def get_post(context, author, permlink, observer=None):
    """Fetch a single post"""
    # pylint: disable=unused-variable
    #TODO: `observer` logic for user-post state
    db = context['db']
    valid_account(author)
    valid_permlink(permlink)

    blacklists_for_user = None
    if observer and context:
        blacklists_for_user = await Mutes.get_blacklists_for_observer(observer, context)

    sql = "---bridge_api.get_post\n" + SQL_TEMPLATE + """ hp.author = :author AND hp.permlink = :permlink """

    result = await db.query_all(sql, author=author, permlink=permlink)
    assert len(result) == 1, 'invalid author/permlink or post not found in cache'
    post = _bridge_post_object(result[0])
    post['active_votes'] = await find_votes_impl(db, author, permlink, VotesPresentation.BridgeApi)
    post = await append_statistics_to_post(post, result[0], False, blacklists_for_user)
    return post

@return_error_info
async def _get_ranked_posts_for_observer_communities( db, sort:str, start_author:str, start_permlink:str, limit, observer:str):
    async def execute_observer_community_query(db, sql, limit):
        return await db.query_all(sql, observer=observer, author=start_author, permlink=start_permlink, limit=limit )

    if not observer:
        return []

    if sort == 'trending':
        sql = "SELECT * FROM bridge_get_ranked_post_by_trends_for_observer_communities( (:observer)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_observer_community_query(db, sql, limit)

    if sort == 'created':
        sql = "SELECT * FROM bridge_get_ranked_post_by_created_for_observer_communities( (:observer)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_observer_community_query(db, sql, limit)

    if sort == 'hot':
        sql = "SELECT * FROM bridge_get_ranked_post_by_hot_for_observer_communities( (:observer)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_observer_community_query(db, sql, limit)

    if sort == 'promoted':
        sql = "SELECT * FROM bridge_get_ranked_post_by_promoted_for_observer_communities( (:observer)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_observer_community_query(db, sql, limit)

    if sort == 'payout':
        sql = "SELECT * FROM bridge_get_ranked_post_by_payout_for_observer_communities( (:observer)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_observer_community_query(db, sql, limit)

    if sort == 'payout_comments':
        sql = "SELECT * FROM bridge_get_ranked_post_by_payout_comments_for_observer_communities( (:observer)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_observer_community_query(db, sql, limit)

    if sort == 'muted':
        sql = "SELECT * FROM bridge_get_ranked_post_by_muted_for_observer_communities( (:observer)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_observer_community_query(db, sql, limit)

    assert False, "Unknown sort order"

@return_error_info
async def _get_ranked_posts_for_communities( db, sort:str, community, start_author:str, start_permlink:str, limit):
    async def execute_community_query(db, sql, limit):
        return await db.query_all(sql, community=community, author=start_author, permlink=start_permlink, limit=limit )

    pinned_sql = "SELECT * FROM bridge_get_ranked_post_pinned_for_community( (:community)::VARCHAR, (:limit)::SMALLINT )"
    # missing paging which results in inability to get all pinned posts
    # and/or causes the same posts to be on each page (depending on limit and number of pinned)
    if sort == 'hot':
        sql = "SELECT * FROM bridge_get_ranked_post_by_hot_for_community( (:community)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_community_query(db, sql, limit)

    if sort == 'trending':
        result_with_pinned_posts = []
        sql = "SELECT * FROM bridge_get_ranked_post_by_trends_for_community( (:community)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        result_with_pinned_posts = await execute_community_query(db, pinned_sql, limit)
        limit -= len(result_with_pinned_posts)
        if limit > 0:
            result_with_pinned_posts += await execute_community_query(db, sql, limit)
        return result_with_pinned_posts

    if sort == 'promoted':
        sql = "SELECT * FROM bridge_get_ranked_post_by_promoted_for_community( (:community)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_community_query(db, sql, limit)

    if sort == 'created':
        sql = "SELECT * FROM bridge_get_ranked_post_by_created_for_community( (:community)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        result_with_pinned_posts = await execute_community_query(db, pinned_sql, limit)
        limit -= len(result_with_pinned_posts)
        if limit > 0:
            result_with_pinned_posts += await execute_community_query(db, sql, limit)
        return result_with_pinned_posts

    if sort == 'muted':
        sql = "SELECT * FROM bridge_get_ranked_post_by_muted_for_community( (:community)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_community_query(db, sql, limit)

    if sort == 'payout':
        sql = "SELECT * FROM bridge_get_ranked_post_by_payout_for_community( (:community)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_community_query(db, sql, limit)

    if sort == 'payout_comments':
        sql = "SELECT * FROM bridge_get_ranked_post_by_payout_comments_for_community( (:community)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_community_query(db, sql, limit)

    assert False, "Unknown sort order"


@return_error_info
async def _get_ranked_posts_for_tag( db, sort:str, tag, start_author:str, start_permlink:str, limit):
    async def execute_tags_query(db, sql, limit):
        return await db.query_all(sql, tag=tag, author=start_author, permlink=start_permlink, limit=limit )

    if sort == 'hot':
        sql = "SELECT * FROM bridge_get_ranked_post_by_hot_for_tag( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_tags_query(db, sql, limit)

    if sort == 'promoted':
        sql = "SELECT * FROM bridge_get_ranked_post_by_promoted_for_tag( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_tags_query(db, sql, limit)

    if sort == 'payout':
        sql = "SELECT * FROM bridge_get_ranked_post_by_payout_for_tag( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_tags_query(db, sql, limit)

    if sort == 'payout_comments':
        sql = "SELECT * FROM bridge_get_ranked_post_by_payout_comments_for_tag( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_tags_query(db, sql, limit)

    if sort == 'muted':
        sql = "SELECT * FROM bridge_get_ranked_post_by_muted_for_tag( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_tags_query(db, sql, limit)

    if sort == 'trending':
        sql = "SELECT * FROM bridge_get_ranked_post_by_trends_for_tag( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_tags_query(db, sql, limit)

    if sort == 'created':
        sql = "SELECT * FROM bridge_get_ranked_post_by_created_for_tag( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_tags_query(db, sql, limit)

    assert False, "Unknown sort order"

@return_error_info
async def _get_ranked_posts_for_all( db, sort:str, start_author:str, start_permlink:str, limit):
    async def execute_query(db, sql, limit):
        return await db.query_all(sql, author=start_author, permlink=start_permlink, limit=limit )

    if sort == 'trending':
        sql = "SELECT * FROM bridge_get_ranked_post_by_trends( (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_query(db, sql, limit)

    if sort == 'created':
        sql = "SELECT * FROM bridge_get_ranked_post_by_created( (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_query(db, sql, limit)

    if sort == 'hot':
        sql = "SELECT * FROM bridge_get_ranked_post_by_hot( (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_query(db, sql, limit)

    if sort == 'promoted':
        sql = "SELECT * FROM bridge_get_ranked_post_by_promoted( (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_query(db, sql, limit)

    if sort == 'payout':
        sql = "SELECT * FROM bridge_get_ranked_post_by_payout( (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_query(db, sql, limit)

    if sort == 'payout_comments':
        sql = "SELECT * FROM bridge_get_ranked_post_by_payout_comments( (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_query(db, sql, limit)

    if sort == 'muted':
        sql = "SELECT * FROM bridge_get_ranked_post_by_muted( (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_query(db, sql, limit)

    assert False, "Unknown sort order"

@return_error_info
async def get_ranked_posts(context, sort:str, start_author:str='', start_permlink:str='',
                           limit:int=20, tag:str=None, observer:str=None):
    """Query posts, sorted by given method."""

    assert sort in ['trending', 'hot', 'created', 'promoted',
                    'payout', 'payout_comments', 'muted'], 'invalid sort'

    async def process_query_results( sql_result ):
        posts = []
        for row in sql_result:
            post = _bridge_post_object(row)
            post['active_votes'] = await find_votes_impl(db, row['author'], row['permlink'], VotesPresentation.BridgeApi)
            post = await append_statistics_to_post(post, row, False, None)
            posts.append(post)
        return posts

    valid_account(start_author, allow_empty=True)
    valid_permlink(start_permlink, allow_empty=True)
    valid_limit(limit, 100, 20)
    valid_tag(tag, allow_empty=True)

    db = context['db']

    if tag == "my":
        result = await _get_ranked_posts_for_observer_communities(db, sort, start_author, start_permlink, limit, observer)
        return await process_query_results(result)

    if tag and tag[:5] == 'hive-':
        result = await _get_ranked_posts_for_communities(db, sort, tag, start_author, start_permlink, limit)
        return await process_query_results(result)

    if ( tag and tag != "all" ):
        result = await _get_ranked_posts_for_tag(db, sort, tag, start_author, start_permlink, limit)
        return await process_query_results(result)


    result = await _get_ranked_posts_for_all(db, sort, start_author, start_permlink, limit)
    return await process_query_results(result)

async def append_statistics_to_post(post, row, is_pinned, blacklists_for_user=None):
    """ apply information such as blacklists and community names/roles to a given post """
    if not blacklists_for_user:
        post['blacklists'] = Mutes.lists(row['author'], row['author_rep'])
    else:
        post['blacklists'] = []
        if row['author'] in blacklists_for_user:
            blacklists = blacklists_for_user[row['author']]
            for blacklist in blacklists:
                post['blacklists'].append(blacklist)
        reputation = row['author_rep']
        if reputation < 1:
            post['blacklists'].append('reputation-0')
        elif reputation  == 1:
            post['blacklists'].append('reputation-1')

    if 'community_title' in row and row['community_title']:
        post['community'] = row['category']
        post['community_title'] = row['community_title']
        if row['role_id']:
            post['author_role'] = ROLES[row['role_id']]
            post['author_title'] = row['role_title']
        else:
            post['author_role'] = 'guest'
            post['author_title'] = ''
    else:
        post['stats']['gray'] = row['is_grayed']
    post['stats']['hide'] = 'irredeemables' in post['blacklists']
    if is_pinned:
        post['stats']['is_pinned'] = True
    return post

async def _get_account_posts_by_blog(db, account : str, start_author : str, start_permlink : str, limit : int):
  _ids = await cursor.pids_by_blog(db, account, start_author, start_permlink, limit)
  posts = await load_posts(db, _ids)
  for post in posts:
      if post['author'] != account:
          post['reblogged_by'] = [account]
  return posts

async def _get_account_posts_by_feed(db, account : str, start_author : str, start_permlink : str, limit : int):
  _ids = await cursor.pids_by_feed_with_reblog(db, account, start_author, start_permlink, limit)
  return await load_posts_reblogs(db, _ids)

async def _get_account_posts_by_replies(db, account : str, start_author : str, start_permlink : str, limit : int):
  _ids = await cursor.pids_by_replies(db, account, start_author, start_permlink, limit)
  return await load_posts(db, _ids)

async def _get_final_posts(db, sort : str, account, start_author : str, start_permlink : str, limit : int):
  if sort == 'blog':
    return await _get_account_posts_by_blog(db, account, start_author, start_permlink, limit)
  elif sort == 'feed':
    return await _get_account_posts_by_feed(db, account, start_author, start_permlink, limit)
  elif sort == 'replies':
    return await _get_account_posts_by_replies(db, account, start_author, start_permlink, limit)

async def _get_posts(db, sort : str, account, start_author : str, start_permlink : str, limit : int, observer : str ):
  if sort == 'posts':
    sql = "SELECT * FROM bridge_get_account_posts_by_posts( (:account)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
  elif sort == 'comments':
    sql = "SELECT * FROM bridge_get_account_posts_by_comments( (:account)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
  elif sort == 'payout':
    sql = "SELECT * FROM bridge_get_account_posts_by_payout( (:account)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"

  sql_result = await db.query_all(sql, account=account, author=start_author, permlink=start_permlink, limit=limit )
  posts = []
  blacklists_for_user = None
  if observer:
      blacklists_for_user = await Mutes.get_blacklists_for_observer(observer, context)

  for row in sql_result:
      post = _bridge_post_object(row)
      post['active_votes'] = await find_votes_impl(db, row['author'], row['permlink'], VotesPresentation.BridgeApi)
      post = await append_statistics_to_post(post, row, False, blacklists_for_user)
      posts.append(post)
  return posts

@return_error_info
async def get_account_posts(context, sort:str, account:str, start_author:str='', start_permlink:str='',
                            limit:int=20, observer:str=None):
    """Get posts for an account -- blog, feed, comments, or replies."""
    valid_sorts = ['blog', 'feed', 'posts', 'comments', 'replies', 'payout']
    assert sort in valid_sorts, 'invalid account sort'

    db = context['db']

    account =         valid_account(account)
    start_author =    valid_account(start_author, allow_empty=True)
    start_permlink =  valid_permlink(start_permlink, allow_empty=True)
    limit =           valid_limit(limit, 100, 20)

    # pylint: disable=unused-variable
    observer_id = await get_account_id(db, observer) if observer else None # TODO

    if sort == 'blog' or sort == 'feed' or sort == 'replies':
      return await _get_final_posts(db, sort, account, start_author, start_permlink, limit)
    else:
      return await _get_posts(db, sort, account, start_author, start_permlink, limit, observer)


@return_error_info
async def get_relationship_between_accounts(context, account1, account2, observer=None):
    valid_account(account1)
    valid_account(account2)

    db = context['db']

    sql = """
        SELECT state, blacklisted, follow_blacklists FROM hive_follows WHERE
        follower = (SELECT id FROM hive_accounts WHERE name = :account1) AND
        following = (SELECT id FROM hive_accounts WHERE name = :account2)
    """

    sql_result = await db.query_all(sql, account1=account1, account2=account2)

    result = {
        'follows': False,
        'ignores': False,
        'is_blacklisted': False,
        'follows_blacklists': False
    }

    for row in sql_result:
        state = row['state']
        if state == 1:
            result['follows'] = True
        elif state == 2:
            result['ignores'] = True

        if row['blacklisted']:
            result['is_blacklisted'] = True
        if row['follow_blacklists']:
            result['follows_blacklists'] = True

    return result
