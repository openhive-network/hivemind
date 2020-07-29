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

SQL_TEMPLATE = """
        SELECT
            hp.id, 
            hp.author,
            hp.root_author,
            hp.author_rep,
            hp.allow_replies,
            hp.allow_votes,
            hp.allow_curation_rewards,
            hp.root_title,
            hp.beneficiaries,
            hp.max_accepted_payout,
            hp.percent_hbd,
            hp.url,
            hp.permlink,
            hp.root_permlink,
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
            hp.created_at, 
            hp.updated_at, 
            hp.rshares, 
            hp.json,
            hp.is_hidden, 
            hp.is_grayed, 
            hp.total_votes, 
            hp.flag_weight,
            hp.sc_trend, 
            hp.role_title, 
            hp.community_title, 
            hr.role_id,
            hp.is_pinned,
            hp.curator_payout_value
        FROM hive_posts_view hp
        WHERE
    """

#pylint: disable=too-many-arguments, no-else-return

async def _get_post_id(db, author, permlink):
    """Get post_id from hive db."""
    sql = """SELECT id FROM hive_posts
              WHERE author_id = (SELECT id FROM hive_accounts WHERE name = :a)
                AND permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :p)
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

    blacklists_for_user = None
    if observer and context:
        blacklists_for_user = await Mutes.get_blacklists_for_observer(observer, context)

    sql = "---bridge_api.get_post\n" + SQL_TEMPLATE + """ hp.author = :author AND hp.permlink = :permlink AND NOT hp.is_deleted """

    result = await db.query_all(sql, author=author, permlink=permlink)
    assert len(result) == 1, 'invalid author/permlink or post not found in cache'
    post = _condenser_post_object(result[0])
    post = await append_statistics_to_post(post, result[0], False, blacklists_for_user)
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
        sql = SQL_TEMPLATE + """ NOT hp.is_paidout AND hp.depth = 0 AND NOT hp.is_deleted
                                    %s ORDER BY hp.sc_trend DESC, hp.id LIMIT :limit """
    elif sort == 'hot':
        sql = SQL_TEMPLATE + """ NOT hp.is_paidout AND hp.depth = 0 AND NOT hp.is_deleted
                                    %s ORDER BY hp.sc_hot DESC, hp.id LIMIT :limit """
    elif sort == 'created':
        sql = SQL_TEMPLATE + """ hp.depth = 0 AND NOT hp.is_deleted AND NOT hp.is_grayed
                                    %s ORDER BY hp.created_at DESC, hp.id LIMIT :limit """
    elif sort == 'promoted':
        sql = SQL_TEMPLATE + """ hp.depth > 0 AND hp.promoted > 0 AND NOT hp.is_deleted
                                    AND NOT hp.is_paidout %s ORDER BY hp.promoted DESC, hp.id LIMIT :limit """
    elif sort == 'payout':
        sql = SQL_TEMPLATE + """ NOT hp.is_paidout AND NOT hp.is_deleted %s
                                    AND hp.payout_at BETWEEN now() + interval '12 hours' AND now() + interval '36 hours'
                                    ORDER BY hp.payout DESC, hp.id LIMIT :limit """
    elif sort == 'payout_comments':
        sql = SQL_TEMPLATE + """ NOT hp.is_paidout AND NOT hp.is_deleted AND hp.depth > 0
                                    %s ORDER BY hp.payout DESC, hp.id LIMIT :limit """
    elif sort == 'muted':
        sql = SQL_TEMPLATE + """ NOT hp.is_paidout AND NOT hp.is_deleted AND hp.is_grayed
                                    AND hp.payout > 0 %s ORDER BY hp.payout DESC, hp.id LIMIT :limit """

    sql = "---bridge_api.get_ranked_posts\n" + sql

    if start_author and start_permlink:
        if sort == 'trending':
            sql = sql % """ AND hp.sc_trend <= (SELECT sc_trend FROM hive_posts WHERE author_id = (SELECT id FROM hive_accounts WHERE name = :author) AND permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :permlink)) 
                            AND hp.id != (SELECT id FROM hive_posts WHERE author_id = (SELECT id FROM hive_accounts WHERE name = :author) AND permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :permlink)) %s """
        elif sort == 'hot':
            sql = sql % """ AND hp.sc_hot <= (SELECT sc_hot FROM hive_posts WHERE author_id = (SELECT id FROM hive_accounts WHERE name = :author) AND permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :permlink))
                            AND hp.id != (SELECT id FROM hive_posts WHERE author_id = (SELECT id FROM hive_accounts WHERE name = :author) AND permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :permlink)) %s """
        elif sort == 'created':
            sql = sql % """ AND hp.id < (SELECT id FROM hive_posts WHERE author_id = (SELECT id FROM hive_accounts WHERE name = :author) AND permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :permlink)) %s """
        elif sort == 'promoted':
            sql = sql % """ AND hp.promoted <= (SELECT promoted FROM hive_posts WHERE author_id = (SELECT id FROM hive_accounts WHERE name = :author) AND permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :permlink))
                                AND hp.id != (SELECT id FROM hive_posts WHERE author_id = (SELECT id FROM hive_accounts WHERE name = :author) AND permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :permlink)) %s """
        else:
            sql = sql % """ AND hp.payout <= (SELECT payout FROM hive_posts WHERE author_id = (SELECT id FROM hive_accounts WHERE name = :author) AND permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :permlink))
                                AND hp.id != (SELECT id FROM hive_posts WHERE author_id = (SELECT id FROM hive_accounts WHERE name = :author) AND permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :permlink)) %s """
    else:
        sql = sql % """ %s """

    if not tag or tag == 'all':
        sql = sql % """ """
    elif tag == 'my':
        sql = sql % """ AND hp.community_id IN (SELECT community_id FROM hive_subscriptions WHERE account_id =
                        (SELECT id FROM hive_accounts WHERE name = :observer) ) """
    elif tag[:5] == 'hive-':
        if start_author and start_permlink:
            sql = sql % """ AND hp.community_id = (SELECT hive_communities.id FROM hive_communities WHERE name = :community_name ) """
        else:
            sql = sql % """ AND hp.community_name = :community_name """

        if sort == 'trending' or sort == 'created':
            pinned_sql = SQL_TEMPLATE + """ hp.is_pinned AND hp.community_name = :community_name ORDER BY hp.created_at DESC """

    else:
        if sort in ['payout', 'payout_comments']:
            sql = sql % """ AND hp.category = :tag """
        else:
            sql = sql % """ AND EXISTS
                (SELECT NULL
                    FROM hive_post_tags hpt
                    INNER JOIN hive_tag_data htd ON hpt.tag_id=htd.id
                    WHERE hp.id = hpt.post_id AND htd.tag = :tag
                ) """

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
     
    sql = "---bridge_api.get_account_posts\n " + SQL_TEMPLATE + """ %s """
        
    if sort == 'blog':
        ids = await cursor.pids_by_blog(db, account, *start, limit)
        posts = await load_posts(context['db'], ids)
        for post in posts:
            if post['author'] != account:
                post['reblogged_by'] = [account]
        return posts
    elif sort == 'posts':
        sql = sql % """ hp.author = :account AND NOT hp.is_deleted AND hp.depth = 0 %s ORDER BY hp.id DESC LIMIT :limit"""
    elif sort == 'comments':
        sql = sql % """ hp.author = :account AND NOT hp.is_deleted AND hp.depth > 0 %s ORDER BY hp.id DESC, hp.depth LIMIT :limit"""
    elif sort == 'payout':
        sql = sql % """ hp.author = :account AND NOT hp.is_deleted AND NOT hp.is_paidout %s ORDER BY hp.payout DESC, hp.id LIMIT :limit"""
    elif sort == 'feed':
        res = await cursor.pids_by_feed_with_reblog(db, account, *start, limit)
        return await load_posts_reblogs(context['db'], res)
    elif sort == 'replies':
        start = start if start_permlink else (account, None)
        ids = await cursor.pids_by_replies(db, *start, limit)
        return await load_posts(context['db'], ids)

    if start_author and start_permlink:
        sql = sql % """ AND hp.id < (SELECT id FROM hive_posts WHERE author_id = (SELECT id FROM hive_accounts WHERE name = :author) AND permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :permlink)) """
    else:
        sql = sql % """ """
        
    posts = []
    blacklists_for_user = None
    if observer:
        blacklists_for_user = await Mutes.get_blacklists_for_observer(observer, context)
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

