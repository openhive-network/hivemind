"""Bridge API public endpoints for posts"""
from hive.conf import SCHEMA_NAME
from hive.server.common.mute_reasons import MUTED_REASONS
from hive.server.bridge_api.objects import _bridge_post_object, append_statistics_to_post, load_profiles
from hive.server.common.helpers import (
    check_community,
    json_date,
    return_error_info,
    valid_account,
    valid_accounts,
    valid_limit,
    valid_permlink,
    valid_tag,
)
from hive.server.common.mutes import Mutes
from hive.server.database_api.methods import find_votes_impl, VotesPresentation
from hive.server.hive_api.common import get_account_id
from hive.server.hive_api.community import list_top_communities
from hive.utils.account import safe_db_profile_metadata


# pylint: disable=too-many-arguments, no-else-return


@return_error_info
async def get_profile(context, account, observer=None):
    """Load account/profile data."""
    db = context['db']
    account = valid_account(account)
    observer = valid_account(observer, allow_empty=True)

    ret = await load_profiles(db, [account])
    assert ret, f'Account \'{account}\' does not exist'  # should not be needed

    observer_id = await get_account_id(db, observer) if observer else None
    if observer_id:
        await _follow_contexts(db, {ret[0]['id']: ret[0]}, observer_id, True)
    return ret[0]


@return_error_info
async def get_accounts(context, accounts, observer=None):
    """Load accounts/profiles data."""
    db = context['db']

    accounts = valid_accounts(accounts)
    observer = valid_account(observer, allow_empty=True)

    ret = await load_profiles(db, accounts)

    if len(ret) != len(accounts):
        found_accounts = {profile['account'] for profile in ret}
        missing_accounts = [acc for acc in accounts if acc not in found_accounts]
        assert len(ret) == len(accounts), f'Account(s) do not exist: {", ".join(missing_accounts)}'

    observer_id = await get_account_id(db, observer) if observer else None
    if observer_id:
        await _follow_contexts(db, {account['id']: account for account in ret}, observer_id, True)
    return ret


@return_error_info
async def get_trending_topics(context, limit: int = 10, observer: str = None):
    """Return top trending topics across pending posts."""
    # pylint: disable=unused-argument
    # db = context['db']
    # observer_id = await get_account_id(db, observer) if observer else None
    # assert not observer, 'observer not supported'
    limit = valid_limit(limit, 25, 10)
    out = []
    cells = await list_top_communities(context, limit)
    for name, title in cells:
        out.append((name, title or name))
    for tag in ('photography', 'travel', 'gaming', 'crypto', 'newsteem', 'music', 'food'):
        if len(out) < limit:
            out.append((tag, '#' + tag))
    return out


@return_error_info
async def get_post(context, author, permlink, observer=None):
    """Fetch a single post"""
    # pylint: disable=unused-variable
    # TODO: `observer` logic for user-post state
    db = context['db']
    valid_account(author)
    valid_account(observer, allow_empty=True)
    valid_permlink(permlink)

    sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_post( (:author)::VARCHAR, (:permlink)::VARCHAR )"
    result = await db.query_all(sql, author=author, permlink=permlink)

    post = _bridge_post_object(result[0])
    post['active_votes'] = await find_votes_impl(db, author, permlink, VotesPresentation.BridgeApi)
    post['reblogs'] = await count_reblogs(db, result[0]['id'])
    post = append_statistics_to_post(post, result[0], False)
    return post


@return_error_info
async def _get_ranked_posts_for_observer_communities(
    db, sort: str, start_author: str, start_permlink: str, limit, observer: str
):
    async def execute_observer_community_query(db, sql, limit):
        return await db.query_all(sql, observer=observer, author=start_author, permlink=start_permlink, limit=limit)

    if sort == 'trending':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_trends_for_observer_communities( (:observer)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_observer_community_query(db, sql, limit)

    if sort == 'created':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_created_for_observer_communities( (:observer)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_observer_community_query(db, sql, limit)

    if sort == 'hot':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_hot_for_observer_communities( (:observer)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_observer_community_query(db, sql, limit)

    if sort == 'promoted':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_promoted_for_observer_communities( (:observer)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_observer_community_query(db, sql, limit)

    if sort == 'payout':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_payout_for_observer_communities( (:observer)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_observer_community_query(db, sql, limit)

    if sort == 'payout_comments':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_payout_comments_for_observer_communities( (:observer)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_observer_community_query(db, sql, limit)

    if sort == 'muted':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_muted_for_observer_communities( (:observer)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT )"
        return await execute_observer_community_query(db, sql, limit)

    assert False, "Unknown sort order"


@return_error_info
async def _get_ranked_posts_for_communities(
    db, sort: str, community, start_author: str, start_permlink: str, limit, observer: str
):
    async def execute_community_query(db, sql, limit):
        return await db.query_all(
            sql, community=community, author=start_author, permlink=start_permlink, limit=limit, observer=observer
        )

    pinned_sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_pinned_for_community( (:community)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR )"

    if sort == 'hot':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_hot_for_community( (:community)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR )"
        return await execute_community_query(db, sql, limit)

    if sort == 'trending':
        result_with_pinned_posts = []
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_trends_for_community( (:community)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, True, (:observer)::VARCHAR )"
        result_with_pinned_posts = await execute_community_query(db, pinned_sql, limit)
        limit -= len(result_with_pinned_posts)
        if limit > 0:
            result_with_pinned_posts += await execute_community_query(db, sql, limit)
        return result_with_pinned_posts

    if sort == 'promoted':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_promoted_for_community( (:community)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR )"
        return await execute_community_query(db, sql, limit)

    if sort == 'created':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_created_for_community( (:community)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, True, (:observer)::VARCHAR )"
        result_with_pinned_posts = await execute_community_query(db, pinned_sql, limit)
        limit -= len(result_with_pinned_posts)
        if limit > 0:
            result_with_pinned_posts += await execute_community_query(db, sql, limit)
        return result_with_pinned_posts

    if sort == 'muted':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_muted_for_community( (:community)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR )"
        return await execute_community_query(db, sql, limit)

    if sort == 'payout':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_payout_for_community( (:community)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR )"
        return await execute_community_query(db, sql, limit)

    if sort == 'payout_comments':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_payout_comments_for_community( (:community)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR )"
        return await execute_community_query(db, sql, limit)

    assert False, "Unknown sort order"


@return_error_info
async def _get_ranked_posts_for_tag(db, sort: str, tag, start_author: str, start_permlink: str, limit, observer: str):
    async def execute_tags_query(db, sql):
        return await db.query_all(
            sql, tag=tag, author=start_author, permlink=start_permlink, limit=limit, observer=observer
        )

    if sort == 'hot':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_hot_for_tag( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR )"
        return await execute_tags_query(db, sql)

    if sort == 'promoted':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_promoted_for_tag( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR )"
        return await execute_tags_query(db, sql)

    if sort == 'payout':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_payout_for_category( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, True, (:observer)::VARCHAR )"
        return await execute_tags_query(db, sql)

    if sort == 'payout_comments':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_payout_comments_for_category( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR )"
        return await execute_tags_query(db, sql)

    if sort == 'muted':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_muted_for_tag( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR )"
        return await execute_tags_query(db, sql)

    if sort == 'trending':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_trends_for_tag( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR )"
        return await execute_tags_query(db, sql)

    if sort == 'created':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_created_for_tag( (:tag)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR )"
        return await execute_tags_query(db, sql)

    assert False, "Unknown sort order"


@return_error_info
async def _get_ranked_posts_for_all(db, sort: str, start_author: str, start_permlink: str, limit, observer: str):
    async def execute_query(db, sql):
        return await db.query_all(sql, author=start_author, permlink=start_permlink, limit=limit, observer=observer)

    if sort == 'trending':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_trends( (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR )"
        return await execute_query(db, sql)

    if sort == 'created':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_created( (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR )"
        return await execute_query(db, sql)

    if sort == 'hot':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_hot( (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR )"
        return await execute_query(db, sql)

    if sort == 'promoted':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_promoted( (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR )"
        return await execute_query(db, sql)

    if sort == 'payout':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_payout( (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, True, (:observer)::VARCHAR )"
        return await execute_query(db, sql)

    if sort == 'payout_comments':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_payout_comments( (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR )"
        return await execute_query(db, sql)

    if sort == 'muted':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_ranked_post_by_muted( (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR )"
        return await execute_query(db, sql)

    assert False, "Unknown sort order"


@return_error_info
async def get_ranked_posts(
    context,
    sort: str,
    start_author: str = '',
    start_permlink: str = '',
    limit: int = 20,
    tag: str = '',
    observer: str = '',
):
    """Query posts, sorted by given method."""
    supported_sort_list = ['trending', 'hot', 'created', 'promoted', 'payout', 'payout_comments', 'muted']
    assert sort in supported_sort_list, f"Unsupported sort, valid sorts: {', '.join(supported_sort_list)}"

    db = context['db']

    async def process_query_results(sql_result):
        posts = []
        for row in sql_result:
            post = _bridge_post_object(row)
            post['active_votes'] = await find_votes_impl(
                db, row['author'], row['permlink'], VotesPresentation.BridgeApi
            )
            post['reblogs'] = await count_reblogs(db, row['id'])
            post = append_statistics_to_post(post, row, row['is_pinned'])
            posts.append(post)
        return posts

    start_author = valid_account(start_author, allow_empty=True)
    start_permlink = valid_permlink(start_permlink, allow_empty=True)
    limit = valid_limit(limit, 100, 20)
    tag = valid_tag(tag, allow_empty=True)
    observer = valid_account(observer, allow_empty=(tag != "my"))

    if tag == "my":
        result = await _get_ranked_posts_for_observer_communities(
            db, sort, start_author, start_permlink, limit, observer
        )
        return await process_query_results(result)

    if tag and check_community(tag):
        result = await _get_ranked_posts_for_communities(db, sort, tag, start_author, start_permlink, limit, observer)
        return await process_query_results(result)

    if tag and tag != "all":
        result = await _get_ranked_posts_for_tag(db, sort, tag, start_author, start_permlink, limit, observer)
        return await process_query_results(result)

    result = await _get_ranked_posts_for_all(db, sort, start_author, start_permlink, limit, observer)
    return await process_query_results(result)


@return_error_info
async def get_account_posts(
    context,
    sort: str,
    account: str,
    start_author: str = '',
    start_permlink: str = '',
    limit: int = 20,
    observer: str = None,
):
    """Get posts for an account -- blog, feed, comments, or replies."""
    supported_sort_list = ['blog', 'feed', 'posts', 'comments', 'replies', 'payout']
    assert sort in supported_sort_list, f"Unsupported sort, valid sorts: {', '.join(supported_sort_list)}"

    db = context['db']

    account = valid_account(account)
    start_author = valid_account(start_author, allow_empty=True)
    start_permlink = valid_permlink(start_permlink, allow_empty=True)
    observer = valid_account(observer, allow_empty=True)
    limit = valid_limit(limit, 100, 20)
    sql = None
    account_posts = True  # set when only posts (or reblogs) of given account are supposed to be in results
    if sort == 'blog':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_account_posts_by_blog( (:account)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::INTEGER, (:observer)::VARCHAR, True )"
    elif sort == 'feed':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_by_feed_with_reblog((:account)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::INTEGER, (:observer)::VARCHAR)"
    elif sort == 'posts':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_account_posts_by_posts( (:account)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR )"
    elif sort == 'comments':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_account_posts_by_comments( (:account)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR )"
    elif sort == 'replies':
        account_posts = False
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_account_posts_by_replies( (:account)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR, True)"
    elif sort == 'payout':
        sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_account_posts_by_payout( (:account)::VARCHAR, (:author)::VARCHAR, (:permlink)::VARCHAR, (:limit)::SMALLINT, (:observer)::VARCHAR )"

    sql_result = await db.query_all(sql, account=account, author=start_author, permlink=start_permlink, limit=limit, observer=observer)
    posts = []

    for row in sql_result:
        post = _bridge_post_object(row)
        post['active_votes'] = await find_votes_impl(db, row['author'], row['permlink'], VotesPresentation.BridgeApi)
        post['reblogs'] = await count_reblogs(db, row['id'])
        if sort == 'blog':
            if post['author'] != account:
                post['reblogged_by'] = [account]
        elif sort == 'feed':
            reblogged_by = set(row['reblogged_by'])
            reblogged_by.discard(row['author'])  # Eliminate original author of reblogged post
            if reblogged_by:
                reblogged_by_list = list(reblogged_by)
                reblogged_by_list.sort()
                post['reblogged_by'] = reblogged_by_list

        post = append_statistics_to_post(post, row, False if account_posts else row['is_pinned'])
        posts.append(post)
    return posts


@return_error_info
async def get_relationship_between_accounts(context, account1, account2, observer=None, debug=None):
    valid_account(account1)
    valid_account(account2)

    db = context['db']

    sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_relationship_between_accounts( (:account1)::VARCHAR, (:account2)::VARCHAR )"
    sql_result = await db.query_row(sql, account1=account1, account2=account2)

    result = {
        'follows': False,
        'ignores': False,
        'blacklists': False,
        'follows_blacklists': False,
        'follows_muted': False,
    }

    row = dict(sql_result)
    state = row['state']
    if state == 1:
        result['follows'] = True
    elif state == 2:
        result['ignores'] = True

    if row['blacklisted']:
        result['blacklists'] = True
    if row['follow_blacklists']:
        result['follows_blacklists'] = True
    if row['follow_muted']:
        result['follows_muted'] = True

    if isinstance(debug, bool) and debug:
        # result['id'] = row['id']
        # ABW: it just made tests harder as any change could trigger id changes
        # data below is sufficient to see when record was created and updated
        result['created_at'] = json_date(row['created_at']) if row['created_at'] else None
        result['block_num'] = row['block_num']

    return result


@return_error_info
async def does_user_follow_any_lists(context, observer):
    """Tells if given observer follows any blacklist or mute list"""
    observer = valid_account(observer)
    blacklists_for_user = await Mutes.get_blacklists_for_observer(observer, context)

    if len(blacklists_for_user) == 0:
        return False
    else:
        return True


@return_error_info
async def get_follow_list(context, observer, follow_type='blacklisted'):
    """For given observer gives directly blacklisted/muted accounts or
    list of blacklists/mute lists followed by observer
    """
    observer = valid_account(observer)
    valid_types = dict(blacklisted=1, follow_blacklist=2, muted=4, follow_muted=8)
    assert follow_type in valid_types, f"Unsupported follow_type, valid values: {', '.join(valid_types.keys())}"

    db = context['db']

    results = []
    if follow_type == 'follow_blacklist' or follow_type == 'follow_muted':
        blacklists_for_user = await Mutes.get_blacklists_for_observer(
            observer, context, follow_type == 'follow_blacklist', follow_type == 'follow_muted'
        )
        for row in blacklists_for_user:
            metadata = safe_db_profile_metadata(row['posting_json_metadata'], row['json_metadata'])

            # list_data = await get_profile(context, row['list'])
            # metadata = list_data["metadata"]["profile"]
            blacklist_description = metadata["blacklist_description"] if "blacklist_description" in metadata else ''
            muted_list_description = metadata["muted_list_description"] if "muted_list_description" in metadata else ''
            results.append(
                {
                    'name': row['list'],
                    'blacklist_description': blacklist_description,
                    'muted_list_description': muted_list_description,
                }
            )
    else:  # blacklisted or muted
        blacklisted_for_user = await Mutes.get_blacklisted_for_observer(observer, context, valid_types[follow_type])
        for account in blacklisted_for_user.keys():
            results.append({'name': account, 'blacklist_description': '', 'muted_list_description': ''})

    return results


async def _follow_contexts(db, accounts, observer_id, include_mute=False):
    sql = f"""SELECT following, state FROM {SCHEMA_NAME}.hive_follows
              WHERE follower = :account_id AND following IN :ids"""
    rows = await db.query_all(sql, account_id=observer_id, ids=tuple(accounts.keys()))
    for row in rows:
        following_id = row[0]
        state = row[1]
        context = {'followed': state == 1}
        if include_mute and state == 2:
            context['muted'] = True
        accounts[following_id]['context'] = context

    for account in accounts.values():
        if 'context' not in account:
            account['context'] = {'followed': False}

@return_error_info
async def count_reblogs(db, post_id: int):
    sql = f"""SELECT * FROM {SCHEMA_NAME}.get_reblog_count(:post_id)"""
    return await db.query_one(sql, post_id=post_id)

@return_error_info
async def list_muted_reasons_enum(db):
    return MUTED_REASONS
