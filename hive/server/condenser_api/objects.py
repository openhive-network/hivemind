"""Handles building condenser_api-compatible response objects."""

import logging

import ujson as json

from hive.server.common.helpers import get_hive_accounts_info_view_query_string, json_date
from hive.utils.account import safe_db_profile_metadata
from hive.utils.normalize import sbd_amount

log = logging.getLogger(__name__)


# Building of legacy account objects


async def load_accounts(db, names, lite=False):
    """`get_accounts`-style lookup for `get_state` compat layer."""
    sql = get_hive_accounts_info_view_query_string(names, lite)
    rows = await db.query_all(sql, names=tuple(names))
    return [_condenser_account_object(row) for row in rows]


def _condenser_account_object(row):
    """Convert an internal account record into legacy-steemd style."""
    # The member `vote_weight` from `hive_accounts` is removed, so currently the member `net_vesting_shares` is equals to zero.

    profile = safe_db_profile_metadata(row['posting_json_metadata'], row['json_metadata'])

    return {
        'name': row['name'],
        'created': str(row['created_at']),
        'post_count': row['post_count'],
        'reputation': row['reputation'],
        'net_vesting_shares': 0,
        'transfer_history': [],
        'json_metadata': json.dumps(
            {
                'profile': {
                    'name': profile['name'],
                    'about': profile['about'],
                    'website': profile['website'],
                    'location': profile['location'],
                    'cover_image': profile['cover_image'],
                    'profile_image': profile['profile_image'],
                }
            }
        ),
    }


def _condenser_post_object(row, truncate_body=0, get_content_additions=False):
    """Given a hive_posts row, create a legacy-style post object."""
    paid = row['is_paidout']

    full_payout = row['pending_payout'] + row['payout']
    post = {}
    post['author'] = row['author']
    post['permlink'] = row['permlink']

    if not row['category']:
        post['category'] = 'undefined'  # condenser#3424 mitigation
    else:
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
        post['id'] = row['id']  # let's be compatible with old code until this API is supported.
        post['author_rewards'] = row['author_rewards']
        post['max_cashout_time'] = json_date(
            None
        )  # ABW: only relevant up to HF17, timestamp::max for all posts later (and also all paid)
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

        post['children_abs_rshares'] = 0  # see: hive/server/database_api/objects.py:68
        post['total_pending_payout_value'] = '0.000 HBD'  # no data

        if paid:
            post['total_vote_weight'] = 0
            post['vote_rshares'] = 0
            post['net_rshares'] = 0
            post['abs_rshares'] = 0
        else:
            post['total_vote_weight'] = row['total_vote_weight']
            post['vote_rshares'] = (row['rshares'] + row['abs_rshares']) // 2
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
    assert asset == 'HBD', f'unhandled asset {asset}'
    return f"{amount:.3f} HBD"
