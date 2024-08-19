"""Routes then builds a get_state response object"""

import logging

from hive.conf import SCHEMA_NAME
from hive.server.bridge_api.methods import count_reblogs
from hive.server.bridge_api.objects import _bridge_post_object, append_statistics_to_post
from hive.server.common.helpers import return_error_info, valid_account, valid_permlink
from hive.server.database_api.methods import find_votes_impl, VotesPresentation

log = logging.getLogger(__name__)


@return_error_info
async def get_discussion(context, author: str, permlink: str, observer: str = ''):
    """Modified `get_state` thread implementation."""
    db = context['db']

    author = valid_account(author)
    permlink = valid_permlink(permlink)
    observer = valid_account(observer, allow_empty=True)

    sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_discussion(:author,:permlink,:observer)"
    rows = await db.query_all(sql, author=author, permlink=permlink, observer=observer)
    if not rows or len(rows) == 0:
        return {}
    root_id = rows[0]['id']
    all_posts = {}
    root_post = _bridge_post_object(rows[0])
    root_post['active_votes'] = await find_votes_impl(
        db, rows[0]['author'], rows[0]['permlink'], VotesPresentation.BridgeApi
    )
    root_post = append_statistics_to_post(root_post, rows[0], rows[0]['is_pinned'])
    root_post['replies'] = []
    root_post['reblogs'] = await count_reblogs(db, rows[0]['id'])
    all_posts[root_id] = root_post

    parent_to_children_id_map = {}

    for index in range(1, len(rows)):
        parent_id = rows[index]['parent_id']
        if parent_id not in parent_to_children_id_map:
            parent_to_children_id_map[parent_id] = []
        parent_to_children_id_map[parent_id].append(rows[index]['id'])
        post = _bridge_post_object(rows[index])
        post['active_votes'] = await find_votes_impl(
            db, rows[index]['author'], rows[index]['permlink'], VotesPresentation.BridgeApi
        )
        post = append_statistics_to_post(post, rows[index], rows[index]['is_pinned'])
        post['replies'] = []
        post['reblogs'] = await count_reblogs(db, rows[index]['id'])
        all_posts[post['post_id']] = post

    for key in parent_to_children_id_map:
        children = parent_to_children_id_map[key]
        post = all_posts[key]
        for child_id in children:
            post['replies'].append(_ref(all_posts[child_id]))

    # result has to be in form of dictionary of dictionaries {post_ref: post}
    results = {}
    for key in all_posts:
        post_ref = _ref(all_posts[key])
        results[post_ref] = all_posts[key]
    return results


def _ref(post):
    return post['author'] + '/' + post['permlink']
