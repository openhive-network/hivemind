"""Handles building condenser-compatible response objects."""

import logging
import ujson as json

from hive.server.common.mutes import Mutes
from hive.server.common.helpers import json_date
from hive.server.database_api.methods import find_votes_impl, VotesPresentation
from hive.utils.normalize import sbd_amount, rep_log10
from hive.indexer.votes import Votes
from hive.utils.account import safe_db_profile_metadata

ROLES = {-2: 'muted', 0: 'guest', 2: 'member', 4: 'mod', 6: 'admin', 8: 'owner'}

log = logging.getLogger(__name__)

# pylint: disable=too-many-lines

def append_statistics_to_post(post, row, is_pinned, blacklists_for_user=None, override_gray=False):
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
    elif override_gray:
        post['stats']['gray'] = ('irredeemables' in post['blacklists'] or len(post['blacklists']) >= 2)
    else:
        post['stats']['gray'] = row['is_grayed']

    post['stats']['hide'] = 'irredeemables' in post['blacklists']
      # it overrides 'is_hidden' flag from post, is that the intent?
    if is_pinned:
        post['stats']['is_pinned'] = True
    return post

async def load_profiles(db, names):
    """`get_accounts`-style lookup for `get_state` compat layer."""
    sql = """SELECT * FROM hive_accounts_info_view
              WHERE name IN :names"""
    rows = await db.query_all(sql, names=tuple(names))
    return [_bridge_profile_object(row) for row in rows]

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
    # pylint: disable=too-many-locals
    assert ids, 'no ids passed to load_posts_keyed'

    # fetch posts and associated author reps
    sql = """
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
        WHERE hp.id IN :ids
    """
    result = await db.query_all(sql, ids=tuple(ids))

    # TODO: author affiliation?
    posts_by_id = {}
    for row in result:
        row = dict(row)

        post = _bridge_post_object(row, truncate_body=truncate_body)
        post['active_votes'] = await find_votes_impl(db, row['author'], row['permlink'], VotesPresentation.BridgeApi)
        append_statistics_to_post(post, row, row['is_pinned'], None, True)

        posts_by_id[row['id']] = post

    return posts_by_id

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

def _bridge_profile_object(row):
    """Convert an internal account record into legacy-steemd style."""

    blacklists = Mutes.lists(row['name'], row['reputation'])

    #Important. The member `sp` in `stats` is removed, because currently the hivemind doesn't hold any balances.
    # The member `vote_weight` from `hive_accounts` is removed as well.
    profile = safe_db_profile_metadata(row['posting_json_metadata'], row['json_metadata'])

    return {
        'id': row['id'],
        'name': row['name'],
        'created': json_date(row['created_at']),
        'active': json_date(row['active_at']),
        'post_count': row['post_count'],
        'reputation': rep_log10(row['reputation']),
        'blacklists': blacklists,
        'stats': {
            'rank': row['rank'],
            'following': row['following'],
            'followers': row['followers'],
        },
        'metadata': {
            'profile': {'name': profile['name'],
                        'about': profile['about'],
                        'website': profile['website'],
                        'location': profile['location'],
                        'cover_image': profile['cover_image'],
                        'profile_image': profile['profile_image'],
                       }}}

def _bridge_post_object(row, truncate_body=0):
    """Given a hive_posts row, create a legacy-style post object."""
    paid = row['is_paidout']

    post = {}
    post['post_id'] = row['id']
    post['author'] = row['author']
    post['permlink'] = row['permlink']
    post['category'] = row.get('category', 'undefined')

    post['title'] = row['title']
    post['body'] = row['body'][0:truncate_body] if truncate_body else row['body']
    try:
        post['json_metadata'] = json.loads(row['json'])
    except Exception:
        post['json_metadata'] = {}

    post['created'] = json_date(row['created_at'])
    post['updated'] = json_date(row['updated_at'])
    post['depth'] = row['depth']
    post['children'] = row['children']
    post['net_rshares'] = row['rshares']

    post['is_paidout'] = row['is_paidout']
    post['payout_at'] = json_date(row['payout_at'])
    post['payout'] = float(row['payout'] + row['pending_payout'])
    post['pending_payout_value'] = _amount(0 if paid else post['payout'])
    post['author_payout_value'] = _amount(0) # supplemented below
    post['curator_payout_value'] = _amount(0) # supplemented below
    post['promoted'] = _amount(row['promoted'])

    post['replies'] = []
    post['author_reputation'] = rep_log10(row['author_rep'])

    neg_rshares = ( row['rshares'] - row['abs_rshares'] ) // 2 # effectively sum of all negative rshares
    # take negative rshares, divide by 2, truncate 10 digits (plus neg sign),
    #   and count digits. creates a cheap log10, stake-based flag weight.
    #   result: 1 = approx $400 of downvoting stake; 2 = $4,000; etc
    flag_weight = max((len(str(int(neg_rshares / 2))) - 11, 0))

    post['stats'] = {
        'hide': row['is_hidden'],
        'gray': row['is_grayed'],
        'total_votes': row['total_votes'],
        'flag_weight': float(flag_weight)} # TODO: down_weight


    #post['author_reputation'] = rep_to_raw(row['author_rep'])

    post['url'] = row['url']
    post['beneficiaries'] = row['beneficiaries']
    post['max_accepted_payout'] = row['max_accepted_payout']
    post['percent_hbd'] = row['percent_hbd']

    if paid:
        curator_payout = sbd_amount(row['curator_payout_value'])
        post['author_payout_value'] = _amount(row['payout'] - curator_payout)
        post['curator_payout_value'] = _amount(curator_payout)

    # TODO: re-evaluate
    if row['depth'] > 0:
        post['parent_author'] = row['parent_author']
        post['parent_permlink'] = row['parent_permlink_or_category']
        post['title'] = 'RE: ' + row['root_title'] # PostSummary & comment context

    return post

def _amount(amount, asset='HBD'):
    """Return a steem-style amount string given a (numeric, asset-str)."""
    assert asset == 'HBD', 'unhandled asset %s' % asset
    return "%.3f HBD" % amount
