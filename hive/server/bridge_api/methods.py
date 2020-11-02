"""Bridge API public endpoints for posts"""

from hive.server.bridge_api.objects import load_profiles, _bridge_post_object, append_statistics_to_post
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
from hive.server.hive_api.public import get_by_feed_with_reblog_impl

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
    valid_account(observer, allow_empty=True)
    valid_permlink(permlink)

    blacklists_for_user = None
    if observer and context:
        blacklists_for_user = await Mutes.get_blacklists_for_observer(observer, context)

    sql = "SELECT * FROM bridge_get_post( (:author)::VARCHAR, (:permlink)::VARCHAR )"
    result = await db.query_all(sql, author=author, permlink=permlink)

    post = _bridge_post_object(result[0])
    post['active_votes'] = await find_votes_impl(db, author, permlink, VotesPresentation.BridgeApi)
    post = append_statistics_to_post(post, result[0], False, blacklists_for_user)
    return post

@return_error_info
async def _get_ranked_posts_for_observer_communities( db, sort:str, start_author:str, start_permlink:str, limit, observer:str):
    async def execute_observer_community_query(db, sql, limit):
        return await db.query_all(sql, observer=observer, author=start_author, permlink=start_permlink, limit=limit )

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
        sql = "SELECT * FROM bridge_get_ranked_post_by_payout_for_category( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_tags_query(db, sql, limit)

    if sort == 'payout_comments':
        sql = "SELECT * FROM bridge_get_ranked_post_by_payout_comments_for_category( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
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
    supported_sort_list = ['trending', 'hot', 'created', 'promoted', 'payout', 'payout_comments', 'muted']
    assert sort in supported_sort_list, "Unsupported sort, valid sorts: {}".format(", ".join(supported_sort_list))

    db = context['db']

    async def process_query_results( sql_result ):
        blacklists_for_user = None
        if observer:
            blacklists_for_user = await Mutes.get_blacklists_for_observer(observer, context)
        posts = []
        for row in sql_result:
            post = _bridge_post_object(row)
            post['active_votes'] = await find_votes_impl(db, row['author'], row['permlink'], VotesPresentation.BridgeApi)
            post = append_statistics_to_post(post, row, row['is_pinned'], blacklists_for_user)
            posts.append(post)
        return posts

    valid_account(start_author, allow_empty=True)
    valid_permlink(start_permlink, allow_empty=True)
    valid_limit(limit, 100, 20)
    valid_tag(tag, allow_empty=True)
    valid_account(observer, allow_empty=(tag != "my"))

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

async def _get_account_posts_by_feed(db, account : str, start_author : str, start_permlink : str, limit : int):
  return await get_by_feed_with_reblog_impl(db, account, start_author, start_permlink, limit)

@return_error_info
async def get_account_posts(context, sort:str, account:str, start_author:str='', start_permlink:str='',
                            limit:int=20, observer:str=None):
    """Get posts for an account -- blog, feed, comments, or replies."""
    supported_sort_list = ['blog', 'feed', 'posts', 'comments', 'replies', 'payout']
    assert sort in supported_sort_list, "Unsupported sort, valid sorts: {}".format(", ".join(supported_sort_list))

    db = context['db']

    account =         valid_account(account)
    start_author =    valid_account(start_author, allow_empty=True)
    start_permlink =  valid_permlink(start_permlink, allow_empty=True)
    observer =        valid_account(observer, allow_empty=True)
    limit =           valid_limit(limit, 100, 20)

    sql = None
    account_posts = True # set when only posts (or reblogs) of given account are supposed to be in results
    if sort == 'blog':
        sql = "SELECT * FROM bridge_get_account_posts_by_blog( (:account)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
    elif sort == 'feed':
        return await _get_account_posts_by_feed(db, account, start_author, start_permlink, limit)
    elif sort == 'posts':
        sql = "SELECT * FROM bridge_get_account_posts_by_posts( (:account)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
    elif sort == 'comments':
        sql = "SELECT * FROM bridge_get_account_posts_by_comments( (:account)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
    elif sort == 'replies':
        account_posts = False
        sql = "SELECT * FROM bridge_get_account_posts_by_replies( (:account)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
    elif sort == 'payout':
        sql = "SELECT * FROM bridge_get_account_posts_by_payout( (:account)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"

    sql_result = await db.query_all(sql, account=account, author=start_author, permlink=start_permlink, limit=limit )
    posts = []
    blacklists_for_user = None
    if observer and account_posts:
        # it looks like the opposite would make more sense, that is, to handle observer for 'blog', 'feed' and 'replies',
        # since that's when posts can come from various authors, some blacklisted and some not, but original version
        # ignored it (only) in those cases
        blacklists_for_user = await Mutes.get_blacklists_for_observer(observer, context)

    for row in sql_result:
        post = _bridge_post_object(row)
        post['active_votes'] = await find_votes_impl(db, row['author'], row['permlink'], VotesPresentation.BridgeApi)
        if sort == 'blog':
          if post['author'] != account:
            post['reblogged_by'] = [account]
        post = append_statistics_to_post(post, row, False if account_posts else row['is_pinned'], blacklists_for_user, not account_posts)
        posts.append(post)
    return posts

    return await _get_posts(db, sort, account, start_author, start_permlink, limit, observer)


@return_error_info
async def get_relationship_between_accounts(context, account1, account2, observer=None):
    valid_account(account1)
    valid_account(account2)

    db = context['db']

    sql = "SELECT * FROM bridge_get_relationship_between_accounts( (:account1)::VARCHAR, (:account2)::VARCHAR )"
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

@return_error_info
async def does_user_follow_any_lists(context, observer):
    follows_blacklists = await get_follow_list(context, observer, 'follow_blacklist')
    follows_muted = await get_follow_list(context, observer, 'follow_muted')

    if len(follows_blacklists) == 0 and len(follows_muted) == 0:
        return False
    else:
        return True

@return_error_info
async def get_follow_list(context, observer, follow_type='blacklisted'):
    db = context['db']
    valid_account(observer)

    valid_types = ['blacklisted', 'follow_blacklist', 'muted', 'follow_muted']
    assert follow_type in valid_types, 'invalid follow_type'

    account_data = get_profile(context, observer)
    metadata = account_data["metadata"]["profile"]
    blacklist_description = metadata["blacklist_description"] if "blacklist_description" in metadata else ''
    muted_list_description = metadata["muted_list_description"] if "muted_list_description" in metadata else ''

    results = []
    if follow_type == 'follow_blacklist':
        sql = """select hive_accounts.name
                 from hive_accounts join hive_follows on (hive_accounts.id = hive_follows.following) where
                 hive_follows.follower = (select id from hive_accounts where name = :observer) and follow_blacklists"""
        sql_result = await db.query_all(sql, observer=observer)
        for row in sql_result:
            row_result = {'name': row['name'], 'blacklist_description': blacklist_description, 'muted_list_description': muted_list_description}
            results.append(row_result)
        return results

    elif follow_type == 'follow_muted':
        sql = """select hive_accounts.name,
                 from hive_accounts join hive_follows on (hive_accounts.id = hive_follows.following) where
                 hive_follows.follower = (select id from hive_accounts where name = :observer) and follow_muted"""
        sql_result = await db.query_all(sql, observer=observer)
        for row in sql_result:
            row_result = {'name': row['name'], 'blacklist_description': blacklist_description, 'muted_list_description': muted_list_description}
            results.append(row_result)
        return results

    blacklists_for_user = await Mutes.get_blacklists_for_observer(observer, context)
    if follow_type == 'blacklisted':
        results.extend([{'name': account, 'blacklist_description':'', 'muted_list_description':''} for account, sources in blacklists_for_user.items() if 'my_blacklist' in sources])
    elif follow_type == 'follow_blacklist':
        results.extend([{'name': account, 'blacklist_description':'', 'muted_list_description':''} for account, sources in blacklists_for_user.items() if 'my_followed_blacklists' in sources])
    elif follow_type == 'muted':
        results.extend([{'name': account, 'blacklist_description':'', 'muted_list_description':''} for account, sources in blacklists_for_user.items() if 'my_muted' in sources])
    elif follow_type == 'follow_muted':
        results.extend([{'name': account, 'blacklist_description':'', 'muted_list_description':''} for account, sources in blacklists_for_user.items() if 'my_followed_mutes' in sources])
    return results
