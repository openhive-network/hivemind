"""Handles building condenser_api-compatible response objects."""

import logging
import ujson as json

from hive.utils.normalize import sbd_amount
from hive.server.common.mutes import Mutes
from hive.server.common.helpers import json_date, get_hive_accounts_info_view_query_string
from hive.server.database_api.methods import find_votes_impl, VotesPresentation
from hive.utils.account import safe_db_profile_metadata

log = logging.getLogger(__name__)

# Building of legacy account objects

async def load_accounts(db, names, lite = False):
    """`get_accounts`-style lookup for `get_state` compat layer."""
    sql = get_hive_accounts_info_view_query_string( names, lite )
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
        hp.author,
        hp.author_rep,
        hp.permlink,
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
        hp.json as json,
        hp.is_hidden,
        hp.is_grayed,
        hp.total_votes,
        hp.parent_author,
        hp.parent_permlink_or_category,
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
        hp.root_title,
        hp.is_muted
    FROM hive_posts_view hp
    WHERE hp.id IN :ids"""

    result = await db.query_all(sql, ids=tuple(ids))

    muted_accounts = Mutes.all()
    posts_by_id = {}
    for row in result:
        row = dict(row)
        post = _condenser_post_object(row, truncate_body=truncate_body)

        post['active_votes'] = await find_votes_impl(db, row['author'], row['permlink'], VotesPresentation.CondenserApi)
        post['active_votes'] = _mute_votes(post['active_votes'], muted_accounts)
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
                    hp.id, ha_a.name as author, hpd_p.permlink as permlink, hp.depth, hp.created_at
                FROM
                    hive_posts hp
                INNER JOIN hive_accounts ha_a ON ha_a.id = hp.author_id
                INNER JOIN hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id
                WHERE hp.id = :id """
            post = await db.query_row(sql, id=_id)
            if post is None:
                # TODO: This should never happen. See #173 for analysis
                log.error("missing post: id %i", _id)
            else:
                log.info("requested deleted post: %s", dict(post))

    return [posts_by_id[_id] for _id in ids]

def _condenser_account_object(row):
    """Convert an internal account record into legacy-steemd style."""
    #The member `vote_weight` from `hive_accounts` is removed, so currently the member `net_vesting_shares` is equals to zero.

    profile = safe_db_profile_metadata(row['posting_json_metadata'], row['json_metadata'])

    return {
        'name': row['name'],
        'created': str(row['created_at']),
        'post_count': row['post_count'],
        'reputation': row['reputation'],
        'net_vesting_shares': 0,
        'transfer_history': [],
        'json_metadata': json.dumps({
            'profile': {'name': profile['name'],
                        'about': profile['about'],
                        'website': profile['website'],
                        'location': profile['location'],
                        'cover_image': profile['cover_image'],
                        'profile_image': profile['profile_image'],
                       }})}

def _condenser_post_object(row, truncate_body=0, get_content_additions=False):
    """Given a hive_posts row, create a legacy-style post object."""
    paid = row['is_paidout']

    # condenser#3424 mitigation
    if not row['category']:
        row['category'] = 'undefined'

    full_payout = row['pending_payout'] + row['payout'];
    post = {}
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

    post['last_payout'] = json_date(row['payout_at'] if paid else None)
    post['cashout_time'] = json_date(None if paid else row['payout_at'])

    post['total_payout_value'] = _amount(row['payout'] if paid else 0)
    post['curator_payout_value'] = _amount(0)

    post['pending_payout_value'] = _amount(0 if paid else full_payout)
    post['promoted'] = _amount(row['promoted'])

    post['replies'] = []
    post['body_length'] = len(row['body'])
    post['author_reputation'] = row['author_rep']

    post['parent_author'] = row['parent_author']
    post['parent_permlink'] = row['parent_permlink_or_category']

    post['url'] = row['url']
    post['root_title'] = row['root_title']
    post['beneficiaries'] = row['beneficiaries']
    post['max_accepted_payout'] = row['max_accepted_payout']
    post['percent_hbd'] = row['percent_hbd']

    if get_content_additions:
        post['id'] = row['id'] # let's be compatible with old code until this API is supported.
        post['active'] = json_date(row['active'])
        post['author_rewards'] = row['author_rewards']
        post['max_cashout_time'] = json_date(None) # ABW: only relevant up to HF17, timestamp::max for all posts later (and also all paid) 
        curator_payout = sbd_amount(row['curator_payout_value'])
        post['curator_payout_value'] = _amount(curator_payout)
        post['total_payout_value'] = _amount(row['payout'] - curator_payout)

        post['reward_weight'] = 10000

        post['root_author'] = row['root_author']
        post['root_permlink'] = row['root_permlink']

        post['allow_replies'] = row['allow_replies']
        post['allow_votes'] = row['allow_votes']
        post['allow_curation_rewards'] = row['allow_curation_rewards']
        post['reblogged_by'] = []
        post['net_votes'] = row['net_votes']

        post['children_abs_rshares'] = 0    # see: hive/server/database_api/objects.py:68
        post['total_pending_payout_value'] = '0.000 HBD'      # no data

        if paid:
            post['total_vote_weight'] = 0
            post['vote_rshares'] = 0
            post['net_rshares'] = 0
            post['abs_rshares'] = 0
        else:
            post['total_vote_weight'] = row['total_vote_weight']
            post['vote_rshares'] = ( row['rshares'] + row['abs_rshares'] ) // 2
            post['net_rshares'] = row['rshares']
            post['abs_rshares'] = row['abs_rshares']
    else:
        post['post_id'] = row['id']
        post['net_rshares'] = row['rshares']
        if paid:
            curator_payout = sbd_amount(row['curator_payout_value'])
            post['curator_payout_value'] = _amount(curator_payout)
            post['total_payout_value'] = _amount(row['payout'] - curator_payout)

    return post

def _amount(amount, asset='HBD'):
    """Return a steem-style amount string given a (numeric, asset-str)."""
    assert asset == 'HBD', 'unhandled asset %s' % asset
    return "%.3f HBD" % amount
