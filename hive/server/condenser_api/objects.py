"""Handles building condenser_api-compatible response objects."""

import logging
import ujson as json

from hive.utils.normalize import sbd_amount, rep_to_raw
from hive.server.common.mutes import Mutes
from hive.server.common.helpers import json_date
from hive.server.database_api.methods import find_votes, VotesPresentation

log = logging.getLogger(__name__)

# Building of legacy account objects

async def load_accounts(db, names):
    """`get_accounts`-style lookup for `get_state` compat layer."""
    sql = """SELECT id, name, display_name, about, reputation, vote_weight,
                    created_at, post_count, profile_image, location, website,
                    cover_image
               FROM hive_accounts WHERE name IN :names"""
    rows = await db.query_all(sql, names=tuple(names))
    return [_condenser_account_object(row) for row in rows]

async def load_posts_reblogs(db, ids_with_reblogs, truncate_body=0):
    """Given a list of (id, reblogged_by) tuples, return posts w/ reblog key."""
    post_ids = [r[0] for r in ids_with_reblogs]
    reblog_by = dict(ids_with_reblogs)
    posts = await load_posts(db, post_ids, truncate_body=truncate_body)

    # Merge reblogged_by data into result set
    for post in posts:
        rby = set(reblog_by[post['post_id']].split(','))
        rby.discard(post['author'])
        if rby:
            post['reblogged_by'] = list(rby)

    return posts

async def load_posts_keyed(db, ids, truncate_body=0):
    """Given an array of post ids, returns full posts objects keyed by id."""
    assert ids, 'no ids passed to load_posts_keyed'

    # fetch posts and associated author reps
    sql = """
    SELECT hp.id,
        hp.community_id,
        hp.author,
        hp.permlink,
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
        hp.json as json,
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
    FROM hive_posts_view hp
    WHERE hp.id IN :ids"""

    result = await db.query_all(sql, ids=tuple(ids))
    author_reps = await _query_author_rep_map(db, result)

    muted_accounts = Mutes.all()
    posts_by_id = {}
    for row in result:
        row = dict(row)
        row['author_rep'] = author_reps[row['author']]
        post = _condenser_post_object(row, truncate_body=truncate_body)

        post['active_votes'] = await find_votes({'db':db}, {'author':row['author'], 'permlink':row['permlink']}, VotesPresentation.CondenserApi)
        posts_by_id[row['id']] = post

    return posts_by_id

def _mute_votes(votes, muted_accounts):
    if not muted_accounts:
        return votes
    return [v for v in votes if v['voter'] not in muted_accounts]

async def load_posts(db, ids, truncate_body=0):
    """Given an array of post ids, returns full objects in the same order."""
    if not ids:
        return []

    # posts are keyed by id so we can return output sorted by input order
    posts_by_id = await load_posts_keyed(db, ids, truncate_body=truncate_body)

    # in rare cases of cache inconsistency, recover and warn
    missed = set(ids) - posts_by_id.keys()
    if missed:
        log.info("get_posts do not exist in cache: %s", repr(missed))
        for _id in missed:
            ids.remove(_id)
            sql = """
                SELECT
                    hp.id, ha_a.name as author, hpd_p.permlink as permlink, depth, created_at, is_deleted
                FROM
                    hive_posts hp
                INNER JOIN hive_accounts ha_a ON ha_a.id = hp.author_id
                INNER JOIN hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id
                WHERE id = :id"""
            post = await db.query_row(sql, id=_id)
            if not post['is_deleted']:
                # TODO: This should never happen. See #173 for analysis
                log.error("missing post -- %s", dict(post))
            else:
                log.info("requested deleted post: %s", dict(post))

    return [posts_by_id[_id] for _id in ids]

async def resultset_to_posts(db, resultset, truncate_body=0):
    author_reps = await _query_author_rep_map(db, resultset)
    muted_accounts = Mutes.all()

    posts = []
    for row in resultset:
        row = dict(row)
        row['author_rep'] = author_reps[row['author']]
        post = _condenser_post_object(row, truncate_body=truncate_body)
        post['active_votes'] = await find_votes({'db':db}, {'author':row['author'], 'permlink':row['permlink']}, VotesPresentation.CondenserApi)
        posts.append(post)

    return posts

async def _query_author_rep_map(db, posts):
    """Given a list of posts, returns an author->reputation map."""
    if not posts:
        return {}
    names = tuple({post['author'] for post in posts})
    sql = "SELECT name, reputation FROM hive_accounts WHERE name IN :names"
    return {r['name']: r['reputation'] for r in await db.query_all(sql, names=names)}

def _condenser_account_object(row):
    """Convert an internal account record into legacy-steemd style."""
    return {
        'name': row['name'],
        'created': str(row['created_at']),
        'post_count': row['post_count'],
        'reputation': rep_to_raw(row['reputation']),
        'net_vesting_shares': row['vote_weight'],
        'transfer_history': [],
        'json_metadata': json.dumps({
            'profile': {'name': row['display_name'],
                        'about': row['about'],
                        'website': row['website'],
                        'location': row['location'],
                        'cover_image': row['cover_image'],
                        'profile_image': row['profile_image'],
                       }})}

def _condenser_post_object(row, truncate_body=0):
    """Given a hive_posts row, create a legacy-style post object."""
    paid = row['is_paidout']

    # condenser#3424 mitigation
    if not row['category']:
        row['category'] = 'undefined'

    post = {}
    post['post_id'] = row['id']
    post['author'] = row['author']
    post['permlink'] = row['permlink']
    post['category'] = row['category']

    post['title'] = row['title']
    post['body'] = row['body'][0:truncate_body] if truncate_body else row['body']
    post['json_metadata'] = row['json']

    post['created'] = json_date(row['created_at'])
    post['last_update'] = json_date(row['updated_at'])
    post['depth'] = row['depth']
    post['children'] = row['children']
    post['net_rshares'] = row['rshares']

    post['last_payout'] = json_date(row['payout_at'] if paid else None)
    post['cashout_time'] = json_date(None if paid else row['payout_at'])
    post['total_payout_value'] = _amount(row['payout'] if paid else 0)
    post['curator_payout_value'] = _amount(0)
    post['pending_payout_value'] = _amount(0 if paid else row['payout'])
    post['promoted'] = _amount(row['promoted'])

    post['replies'] = []
    post['body_length'] = len(row['body'])
    post['author_reputation'] = rep_to_raw(row['author_rep'])

    if row['depth'] > 0:
        post['parent_author'] = row['parent_author']
        post['parent_permlink'] = row['parent_permlink']
    else:
        post['parent_author'] = ''
        post['parent_permlink'] = row['category']

    post['url'] = row['url']
    post['root_title'] = row['root_title']
    post['beneficiaries'] = row['beneficiaries']
    post['max_accepted_payout'] = row['max_accepted_payout']
    post['percent_hbd'] = row['percent_hbd']

    if paid:
        curator_payout = sbd_amount(row['curator_payout_value'])
        post['curator_payout_value'] = _amount(curator_payout)
        post['total_payout_value'] = _amount(row['payout'] - curator_payout)

    return post

def _amount(amount, asset='HBD'):
    """Return a steem-style amount string given a (numeric, asset-str)."""
    assert asset == 'HBD', 'unhandled asset %s' % asset
    return "%.3f HBD" % amount
