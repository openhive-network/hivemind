"""Bridge API public endpoints for posts"""

import hive.server.bridge_api.cursor as cursor
from hive.server.bridge_api.objects import load_posts, load_posts_reblogs, load_profiles, _condenser_post_object
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

SELECT_FRAGMENT = """
    SELECT hive_posts_cache.post_id, hive_posts_cache.author, hive_posts_cache.permlink,
           hive_posts_cache.title, hive_posts_cache.body, hive_posts_cache.category, hive_posts_cache.depth,
           hive_posts_cache.promoted, hive_posts_cache.payout, hive_posts_cache.payout_at,
           hive_posts_cache.is_paidout, hive_posts_cache.children, hive_posts_cache.votes,
           hive_posts_cache.created_at, hive_posts_cache.updated_at, hive_posts_cache.rshares,
           hive_posts_cache.raw_json, hive_posts_cache.json, hive_accounts.reputation AS author_rep,
           hive_posts_cache.is_hidden AS is_hidden, hive_posts_cache.is_grayed AS is_grayed,
           hive_posts_cache.total_votes AS total_votes, hive_posts_cache.flag_weight AS flag_weight,
           hive_posts_cache.sc_trend AS sc_trend, hive_accounts.id AS acct_author_id,
           hive_roles.title as role_title, hive_communities.title AS community_title, hive_roles.role_id AS role_id,
           hive_posts.is_pinned AS is_pinned
           FROM hive_posts_cache JOIN hive_posts ON (hive_posts_cache.post_id = hive_posts.id)
                                 JOIN hive_accounts ON (hive_posts_cache.author = hive_accounts.name)
                                 LEFT OUTER JOIN hive_communities ON (hive_posts_cache.community_id = hive_communities.id)
                                 LEFT OUTER JOIN hive_roles ON (hive_accounts.id = hive_roles.account_id AND hive_posts_cache.community_id = hive_roles.community_id) """

#pylint: disable=too-many-arguments, no-else-return

async def _get_post_id(db, author, permlink):
    """Get post_id from hive db."""
    sql = """SELECT id FROM hive_posts
              WHERE author = :a
                AND permlink = :p
                AND is_deleted = '0'"""
    post_id = await db.query_one(sql, a=author, p=permlink)
    assert post_id, 'invalid author/permlink'
    return post_id

@return_error_info
async def get_profile(context, account, observer=None):
    """Load account/profile data."""
    db = context['db']
    ret = await load_profiles(db, [valid_account(account)])
    if not ret:
        return None

    observer_id = await get_account_id(db, observer) if observer else None
    if observer_id:
        await _follow_contexts(db, {ret[0]['id']: ret[0]}, observer_id, True)
    return ret[0]

@return_error_info
async def get_trending_topics(context, limit=10, observer=None):
    """Return top trending topics across pending posts."""
    # pylint: disable=unused-argument
    #db = context['db']
    #observer_id = await get_account_id(db, observer) if observer else None
    #assert not observer, 'observer not supported'
    limit = valid_limit(limit, 25)
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

    sql = "---bridge_api.get_post\n" + SELECT_FRAGMENT + """ WHERE hive_posts_cache.author = :author AND hive_posts_cache.permlink = :permlink AND NOT hive_posts.is_deleted """

    result = await db.query_all(sql, author=author, permlink=permlink)
    assert len(result) == 1, 'invalid author/permlink or post not found in cache'
    post = _condenser_post_object(result[0])
    blacklists_for_user = Mutes.get_blacklists_for_observer(observer, context)
    post['blacklists'] = await append_statistics_to_post(post, result[0], False, blacklists_for_user)
    return post

@return_error_info
async def get_ranked_posts(context, sort, start_author='', start_permlink='',
                           limit=20, tag=None, observer=None):
    """Query posts, sorted by given method."""

    assert sort in ['trending', 'hot', 'created', 'promoted',
                    'payout', 'payout_comments', 'muted'], 'invalid sort'

    valid_account(start_author, allow_empty=True)
    valid_permlink(start_permlink, allow_empty=True)
    valid_limit(limit, 100)
    valid_tag(tag, allow_empty=True)

    db = context['db']

    sql = ''
    pinned_sql = ''

    if sort == 'trending':
        sql = SELECT_FRAGMENT + """ WHERE NOT hive_posts_cache.is_paidout AND hive_posts_cache.depth = 0 AND NOT hive_posts.is_deleted
                                    %s ORDER BY sc_trend desc, post_id LIMIT :limit """
    elif sort == 'hot':
        sql = SELECT_FRAGMENT + """ WHERE NOT hive_posts_cache.is_paidout AND hive_posts_cache.depth = 0 AND NOT hive_posts.is_deleted
                                    %s ORDER BY sc_hot desc, post_id LIMIT :limit """
    elif sort == 'created':
        sql = SELECT_FRAGMENT + """ WHERE hive_posts_cache.depth = 0 AND NOT hive_posts.is_deleted AND NOT hive_posts_cache.is_grayed
                                    %s ORDER BY hive_posts_cache.created_at DESC, post_id LIMIT :limit """
    elif sort == 'promoted':
        sql = SELECT_FRAGMENT + """ WHERE hive_posts_cache.depth > 0 AND hive_posts_cache.promoted > 0 AND NOT hive_posts.is_deleted
                                    AND NOT hive_posts_cache.is_paidout %s ORDER BY hive_posts_cache.promoted DESC, post_id LIMIT :limit """
    elif sort == 'payout':
        sql = SELECT_FRAGMENT + """ WHERE NOT hive_posts_cache.is_paidout AND NOT hive_posts.is_deleted %s
                                    AND payout_at BETWEEN now() + interval '12 hours' AND now() + interval '36 hours'
                                    ORDER BY hive_posts_cache.payout DESC, post_id LIMIT :limit """
    elif sort == 'payout_comments':
        sql = SELECT_FRAGMENT + """ WHERE NOT hive_posts_cache.is_paidout AND NOT hive_posts.is_deleted AND hive_posts_cache.depth > 0
                                    %s ORDER BY hive_posts_cache.payout DESC, post_id LIMIT :limit """
    elif sort == 'muted':
        sql = SELECT_FRAGMENT + """ WHERE NOT hive_posts_cache.is_paidout AND NOT hive_posts.is_deleted AND hive_posts_cache.is_grayed
                                    AND hive_posts_cache.payout > 0 %s ORDER BY hive_posts_cache.payout DESC, post_id LIMIT :limit """

    sql = "---bridge_api.get_ranked_posts\n" + sql

    if start_author and start_permlink:
        if sort == 'trending':
            sql = sql % """ AND hive_posts_cache.sc_trend <= (SELECT sc_trend FROM hive_posts_cache WHERE permlink = :permlink AND author = :author) 
                            AND hive_posts_cache.post_id != (SELECT post_id FROM hive_posts_cache WHERE permlink = :permlink AND author=:author) %s """
        elif sort == 'hot':
            sql = sql % """ AND hive_posts_cache.sc_hot <= (SELECT sc_hot FROM hive_posts_cache WHERE permlink = :permlink AND author = :author)
                            AND hive_posts_cache.post_id != (SELECT post_id FROM hive_posts_cache WHERE permlink = :permlink AND author = :author) %s """
        elif sort == 'created':
            sql = sql % """ AND hive_posts_cache.post_id < (SELECT post_id FROM hive_posts_cache WHERE permlink = :permlink AND author = :author) %s """
        elif sort == 'promoted':
            sql = sql % """ AND hive_posts_cache.promoted <= (SELECT promoted FROM hive_posts_cache WHERE permlink = :permlink AND author = :author)
                                AND hive_posts_cache.post_id != (SELECT post_id FROM hive_posts_cache WHERE permlink = :permlink AND author = :author) %s """
        else:
            sql = sql % """ AND hive_posts_cache.payout <= (SELECT payout FROM hive_posts_cache WHERE permlink = :permlink AND author = :author)
                                AND hive_posts_cache.post_id != (SELECT post_id FROM hive_posts_cache WHERE permlink = :permlink AND author = :author) %s """
    else:
        sql = sql % """ %s """

    if not tag or tag == 'all':
        sql = sql % """ """
    elif tag == 'my':
        sql = sql % """ AND hive_posts_cache.community_id IN (SELECT community_id FROM hive_subscriptions WHERE account_id =
                        (SELECT id FROM hive_accounts WHERE name = :observer) ) """
    elif tag[:5] == 'hive-':
        if start_author and start_permlink:
            sql = sql % """  AND hive_posts_cache.community_id = (SELECT hive_communities.id FROM hive_communities WHERE name = :community_name ) """
        else:
            sql = sql % """ AND hive_communities.name = :community_name """

        if sort == 'trending' or sort == 'created':
                pinned_sql = SELECT_FRAGMENT + """ WHERE is_pinned AND hive_communities.name = :community_name ORDER BY hive_posts_cache.created_at DESC """

    else:
        if sort in ['payout', 'payout_comments']:
            sql = sql % """ AND hive_posts_cache.category = :tag """
        else:
            sql = sql % """ AND hive_posts_cache.post_id IN (SELECT post_id FROM hive_post_tags WHERE tag = :tag)"""

    if not observer:
        observer = ''

    posts = []
    pinned_post_ids = []

    blacklists_for_user = None
    if observer and context:
        blacklists_for_user = await Mutes.get_blacklists_for_observer(observer, context)

    if pinned_sql:
        pinned_result = await db.query_all(pinned_sql, author=start_author, limit=limit, tag=tag, permlink=start_permlink, community_name=tag, observer=observer)
        for row in pinned_result:
            post = _condenser_post_object(row)
            post = await append_statistics_to_post(post, row, True, blacklists_for_user)
            limit = limit - 1
            posts.append(post)
            pinned_post_ids.append(post['post_id'])

    sql_result = await db.query_all(sql, author=start_author, limit=limit, tag=tag, permlink=start_permlink, community_name=tag, observer=observer)
    for row in sql_result:
        post = _condenser_post_object(row)
        post = await append_statistics_to_post(post, row, False, blacklists_for_user)
        if post['post_id'] in pinned_post_ids:
            continue
        posts.append(post)
    return posts

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
        reputation = int(row['author_rep'])
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

@return_error_info
async def get_account_posts(context, sort, account, start_author='', start_permlink='',
                            limit=20, observer=None):
    """Get posts for an account -- blog, feed, comments, or replies."""
    valid_sorts = ['blog', 'feed', 'posts', 'comments', 'replies', 'payout']
    assert sort in valid_sorts, 'invalid account sort'
    assert account, 'account is required'

    db = context['db']
    account = valid_account(account)
    start_author = valid_account(start_author, allow_empty=True)
    start_permlink = valid_permlink(start_permlink, allow_empty=True)
    start = (start_author, start_permlink)
    limit = valid_limit(limit, 100)

    # pylint: disable=unused-variable
    observer_id = await get_account_id(db, observer) if observer else None # TODO
     
    sql = "---bridge_api.get_account_posts\n " + SELECT_FRAGMENT + """ %s """      
        
    if sort == 'blog':
        ids = await cursor.pids_by_blog(db, account, *start, limit)
        posts = await load_posts(context['db'], ids)
        for post in posts:
            if post['author'] != account:
                post['reblogged_by'] = [account]
        return posts
    elif sort == 'posts':
        sql = sql % """ WHERE hive_posts_cache.author = :account AND NOT hive_posts.is_deleted AND hive_posts_cache.depth = 0 %s ORDER BY hive_posts_cache.post_id DESC LIMIT :limit"""
    elif sort == 'comments':
        sql = sql % """ WHERE hive_posts_cache.author = :account AND NOT hive_posts.is_deleted AND hive_posts_cache.depth > 0 %s ORDER BY hive_posts_cache.post_id DESC, depth LIMIT :limit"""
    elif sort == 'payout':
        sql = sql % """ WHERE hive_posts_cache.author = :account AND NOT hive_posts.is_deleted AND NOT hive_posts_cache.is_paidout %s ORDER BY payout DESC, post_id LIMIT :limit"""
    elif sort == 'feed':
        res = await cursor.pids_by_feed_with_reblog(db, account, *start, limit)
        return await load_posts_reblogs(context['db'], res)
    elif sort == 'replies':
        start = start if start_permlink else (account, None)
        ids = await cursor.pids_by_replies(db, *start, limit)
        return await load_posts(context['db'], ids)

    if start_author and start_permlink:
        sql = sql % """ AND hive_posts_cache.post_id < (SELECT post_id FROM hive_posts_cache WHERE author = :author AND permlink = :permlink) """
    else:
        sql = sql % """ """
        
    posts = []
    blacklists_for_user = None
    if observer:
        blacklists_for_user = Mutes.get_blacklists_for_observer(observer, context)
    sql_result = await db.query_all(sql, account=account, author=start_author, permlink=start_permlink, limit=limit)
    for row in sql_result:
        post = _condenser_post_object(row)
        post = await append_statistics_to_post(post, row, False, blacklists_for_user)
        posts.append(post)
    return posts

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