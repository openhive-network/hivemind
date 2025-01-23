"""Handles building condenser-compatible response objects."""

import logging

import ujson as json

from hive.server.common.mute_reasons import MUTED_REASONS, decode_bitwise_mask
from hive.server.common.helpers import get_hive_accounts_info_view_query_string, json_date
from hive.utils.account import safe_db_profile_metadata
from hive.utils.normalize import rep_log10, sbd_amount

ROLES = {-2: 'muted', 0: 'guest', 2: 'member', 4: 'mod', 6: 'admin', 8: 'owner'}

log = logging.getLogger(__name__)


# pylint: disable=too-many-lines


def append_statistics_to_post(post, row, is_pinned):
    """apply information such as blacklists and community names/roles to a given post"""

    post['blacklists'] = []
    if 'blacklists' in row and row['blacklists']:
        split_lists = row['blacklists'].split(',')
        for blacklist_source in split_lists:
            post['blacklists'].append(blacklist_source)
    reputation = post['author_reputation']
    if reputation < 1:
        post['blacklists'].append('reputation-0')
    elif reputation == 1:
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

    post['stats']['gray'] = row['is_grayed'] or row['is_muted'] or (row['role_id'] == -2)

    post['stats']['muted_reasons'] = decode_bitwise_mask(row['muted_reasons'])
    if row['is_grayed']:
        post['stats']['muted_reasons'].append(MUTED_REASONS['MUTED_REPUTATION'])
    if row['role_id'] == -2:
        post['stats']['muted_reasons'].append(MUTED_REASONS['MUTED_ROLE_COMMUNITY'])

    if len(post['stats']['muted_reasons']) == 0:
        del post['stats']['muted_reasons'] # We do not want to bloat the output with empty arrays

    if is_pinned:
        post['stats']['is_pinned'] = True
    return post


async def load_profiles(db, names):
    """`get_accounts`-style lookup for `get_state` compat layer."""
    sql = get_hive_accounts_info_view_query_string(names)
    rows = await db.query_all(sql, names=tuple(names))
    return [_bridge_profile_object(row) for row in rows]


def _bridge_profile_object(row):
    """Convert an internal account record into legacy-steemd style."""

    # Important. The member `sp` in `stats` is removed, because currently the hivemind doesn't hold any balances.
    # The member `vote_weight` from `hive_accounts` is removed as well.
    profile = safe_db_profile_metadata(row['posting_json_metadata'], row['json_metadata'])

    return {
        'id': row['id'],
        'name': row['name'],
        'created': json_date(row['created_at']),
        'active': json_date(row['active_at']),
        'post_count': row['post_count'],
        'reputation': rep_log10(row['reputation']),
        'blacklists': [],
        'stats': {
            'rank': row['rank'],
            'following': row['following'],
            'followers': row['followers'],
        },
        'metadata': {
            'profile': {
                'name': profile['name'],
                'about': profile['about'],
                'website': profile['website'],
                'location': profile['location'],
                'cover_image': profile['cover_image'],
                'profile_image': profile['profile_image'],
                'blacklist_description': profile['blacklist_description'] if 'blacklist_description' in profile else '',
                'muted_list_description': profile['muted_list_description']
                if 'muted_list_description' in profile
                else '',
            }
        },
    }


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
    post['author_payout_value'] = _amount(0)  # supplemented below
    post['curator_payout_value'] = _amount(0)  # supplemented below

    post['replies'] = []
    post['reblogs'] = 0
    post['author_reputation'] = rep_log10(row['author_rep'])

    neg_rshares = (row['rshares'] - row['abs_rshares']) // 2  # effectively sum of all negative rshares
    # take negative rshares, divide by 2, truncate 10 digits (plus neg sign),
    #   and count digits. creates a cheap log10, stake-based flag weight.
    #   result: 1 = approx $400 of downvoting stake; 2 = $4,000; etc
    flag_weight = max((len(str(int(neg_rshares / 2))) - 11, 0))

    post['stats'] = {
        'hide': row['is_hidden'],
        'gray': row['is_grayed'],
        'total_votes': row['total_votes'],
        'flag_weight': float(flag_weight),
    }  # TODO: down_weight

    # post['author_reputation'] = rep_to_raw(row['author_rep'])

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
        post['title'] = 'RE: ' + row['root_title']  # PostSummary & comment context

    return post


def _amount(amount, asset='HBD'):
    """Return a steem-style amount string given a (numeric, asset-str)."""
    assert asset == 'HBD', f'unhandled asset {asset}'
    return f"{amount:.3f} HBD"
