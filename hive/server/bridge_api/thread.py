"""Routes then builds a get_state response object"""

import logging

from hive.server.bridge_api.objects import load_posts_keyed, _condenser_post_object
from hive.server.bridge_api.methods import append_statistics_to_post
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
    # We thougth this would be covered by "hive_posts_ix4" btree (parent_id, id) WHERE is_deleted = false but it was not
    db = context['db']

    author = valid_account(author)
    permlink = valid_permlink(permlink)

    sql = """
        WITH RECURSIVE child_posts (id, parent_id) AS (
            SELECT id, parent_id FROM hive_posts_view hpv WHERE hpv.author = :author
                AND hpv.permlink = :permlink AND NOT hpv.is_deleted AND NOT hpv.is_muted
            UNION ALL
            SELECT children.id, children.parent_id FROM hive_posts children INNER JOIN child_posts ON (children.parent_id = child_posts.id) 
            WHERE NOT children.is_deleted AND NOT children.is_muted
        )
        SELECT child_posts.id, child_posts.parent_id, hpv.id as post_id, hpv.author, hpv.permlink,
           hpv.title, hpv.body, hpv.category, hpv.depth,
           hpv.promoted, hpv.payout, hpv.payout_at,
           hpv.is_paidout, hpv.children, hpv.votes,
           hpv.created_at, hpv.updated_at, hpv.rshares,
           hpv.json, hpv.author_rep,
           hpv.is_hidden, hpv.is_grayed,
           hpv.total_votes, hpv.flag_weight,
           hpv.sc_trend, hpv.author_id AS acct_author_id,
           hpv.root_author, hpv.root_permlink, hpv.parent_author, hpv.parent_permlink,
           hpv.allow_replies, hpv.allow_votes,
           hpv.allow_curation_rewards, hpv.url, hpv.root_title, hpv.beneficiaries,
           hpv.max_accepted_payout, hpv.percent_hbd, hpv.curator_payout_value
           FROM 
              child_posts 
           INNER JOIN hive_posts_view hpv ON (hpv.id = child_posts.id)
           WHERE NOT hpv.is_deleted AND NOT hpv.is_muted
        LIMIT 2000
    """

    blacklists_for_user = None
    if observer:
        blacklists_for_user = await Mutes.get_blacklists_for_observer(observer, context)

    rows = await db.query_all(sql, author=author, permlink=permlink)
    if not rows or len(rows) == 0:
        return {}
    root_id = rows[0]['id']
    all_posts = {}
    root_post = _condenser_post_object(rows[0])
    root_post = await append_statistics_to_post(root_post, rows[0], False, blacklists_for_user)
    root_post['replies'] = []
    all_posts[root_id] = root_post

    id_to_parent_id_map = {}
    id_to_parent_id_map[root_id] = None

    for index in range(1, len(rows)):
        id_to_parent_id_map[rows[index]['id']] = rows[index]['parent_id']
        post = _condenser_post_object(rows[index])
        post = await append_statistics_to_post(post, rows[index], False, blacklists_for_user)
        post['replies'] = []
        all_posts[post['post_id']] = post

    discussion_map = {}
    build_discussion_map(root_id, id_to_parent_id_map, discussion_map)

    for key in discussion_map:
        children = discussion_map[key]
        if children and len(children) > 0:
            post = all_posts[key]
            for child_id in children:
                post['replies'].append(_ref(all_posts[child_id]))

    #result has to be in form of dictionary of dictionaries {post_ref: post}
    results = {}
    for key in all_posts:
        post_ref = _ref(all_posts[key])
        results[post_ref] = all_posts[key]
    return results

def build_discussion_map(parent_id, posts, results):
    results[parent_id] = get_children(parent_id, posts)
    if results[parent_id] == []:
        return

    for post_id in results[parent_id]:
        build_discussion_map(post_id, posts, results)

def get_children(parent_id, posts):
    results = []
    for key in posts:
        if posts[key] == parent_id:
            results.append(key)
    return results

async def _get_post_id(db, author, permlink):
    """Given an author/permlink, retrieve the id from db."""
    sql = """
        SELECT 
            id 
        FROM hive_posts hp
        INNER JOIN hive_accounts ha_a ON ha_a.id = hp.author_id
        INNER JOIN hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id
        WHERE ha_a.name = :author 
            AND hpd_p.permlink = :permlink 
            AND is_deleted = '0' 
        LIMIT 1"""
    return await db.query_one(sql, a=author, p=permlink)

def _ref(post):
    return post['author'] + '/' + post['permlink']

async def _child_ids(db, parent_ids):
    """Load child ids for multuple parent ids."""
    sql = """
             SELECT parent_id, array_agg(id)
               FROM hive_posts
              WHERE parent_id IN :ids
                AND is_deleted = '0'
           GROUP BY parent_id
    """
    rows = await db.query_all(sql, ids=tuple(parent_ids))
    return [[row[0], row[1]] for row in rows]

async def _load_discussion(db, root_id):
    """Load a full discussion thread."""
    # build `ids` list and `tree` map
    ids = []
    tree = {}
    todo = [root_id]
    while todo:
        ids.extend(todo)
        rows = await _child_ids(db, todo)
        todo = []
        for pid, cids in rows:
            tree[pid] = cids
            todo.extend(cids)

    # load all post objects, build ref-map
    posts = await load_posts_keyed(db, ids)

    # remove posts/comments from muted accounts
    rem_pids = []
    for pid, post in posts.items():
        if post['stats']['hide']:
            rem_pids.append(pid)
    for pid in rem_pids:
        if pid in posts:
            del posts[pid]
        if pid in tree:
            rem_pids.extend(tree[pid])

    refs = {pid: _ref(post) for pid, post in posts.items()}

    # add child refs to parent posts
    for pid, post in posts.items():
        if pid in tree:
            post['replies'] = [refs[cid] for cid in tree[pid]
                               if cid in refs]

    # return all nodes keyed by ref
    return {refs[pid]: post for pid, post in posts.items()}
