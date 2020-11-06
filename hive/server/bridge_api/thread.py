"""Routes then builds a get_state response object"""

import logging

from hive.server.bridge_api.objects import _bridge_post_object, append_statistics_to_post
from hive.server.database_api.methods import find_votes_impl, VotesPresentation
from hive.server.common.helpers import (
    return_error_info,
    valid_account,
    valid_permlink)
from hive.server.common.mutes import Mutes

log = logging.getLogger(__name__)

@return_error_info
async def get_discussion(context, author, permlink, observer=None):
    """Modified `get_state` thread implementation."""
    # New index was created: hive_posts_parent_id_btree (CREATE INDEX "hive_posts_parent_id_btree" ON hive_posts btree(parent_id)
    # We thougth this would be covered by "hive_posts_ix4" btree (parent_id, id) WHERE counter_deleted = 0 but it was not
    db = context['db']

    author = valid_account(author)
    permlink = valid_permlink(permlink)

    blacklists_for_user = None
    if observer:
        blacklists_for_user = await Mutes.get_blacklists_for_observer(observer, context)

    sql = "SELECT * FROM get_discussion(:author,:permlink)"
    rows = await db.query_all(sql, author=author, permlink=permlink)
    if not rows or len(rows) == 0:
        return {}
    root_id = rows[0]['id']
    all_posts = {}
    root_post = _bridge_post_object(rows[0])
    root_post['active_votes'] = await find_votes_impl(db, rows[0]['author'], rows[0]['permlink'], VotesPresentation.BridgeApi)
    root_post = append_statistics_to_post(root_post, rows[0], False, blacklists_for_user)
    if 'should_be_excluded' in root_post and root_post['should_be_excluded']:
        return {}
    root_post.pop('is_muted', '')
    root_post['replies'] = []
    all_posts[root_id] = root_post

    parent_to_children_id_map = {}

    for index in range(1, len(rows)):
        parent_id = rows[index]['parent_id']
        if parent_id not in parent_to_children_id_map:
            parent_to_children_id_map[parent_id] = []
        parent_to_children_id_map[parent_id].append(rows[index]['id'])
        post = _bridge_post_object(rows[index])
        post['active_votes'] = await find_votes_impl(db, rows[index]['author'], rows[index]['permlink'], VotesPresentation.BridgeApi)
        post = append_statistics_to_post(post, rows[index], False, blacklists_for_user)
        if 'should_be_excluded' in post and post['should_be_excluded']:
            continue
        post.pop('is_muted', '')
        post['replies'] = []
        all_posts[post['post_id']] = post

    for key in parent_to_children_id_map:
        children = parent_to_children_id_map[key]
        post = all_posts[key]
        for child_id in children:
            post['replies'].append(_ref(all_posts[child_id]))

    #result has to be in form of dictionary of dictionaries {post_ref: post}
    results = {}
    for key in all_posts:
        post_ref = _ref(all_posts[key])
        results[post_ref] = all_posts[key]
    return results

def _ref(post):
    return post['author'] + '/' + post['permlink']
