from hive.server.common.helpers import json_date
from hive.utils.normalize import sbd_amount, to_nai


def _amount(amount, asset='HBD'):
    """Return a steem-style amount string given a (numeric, asset-str)."""
    assert asset == 'HBD', f'unhandled asset {asset}'
    return f"{amount:.3f} HBD"


def database_post_object(row, truncate_body=0):
    """Given a hive_posts row, create a legacy-style post object."""

    paid = row['is_paidout']

    post = {}
    post['author_rewards'] = row['author_rewards']
    post['id'] = row['id']
    post['author'] = row['author']
    post['permlink'] = row['permlink']
    post['category'] = row['category'] if 'category' in row else 'undefined'

    post['title'] = row['title']
    post['body'] = row['body'][0:truncate_body] if truncate_body else row['body']
    post['json_metadata'] = row['json']

    post['created'] = json_date(row['created_at'])
    post['last_update'] = json_date(row['updated_at'])
    post['depth'] = row['depth']
    post['children'] = row['children']

    post['last_payout'] = json_date(row['last_payout_at'])
    post['cashout_time'] = json_date(row['cashout_time'])
    post['max_cashout_time'] = json_date(
        None
    )  # ABW: only relevant up to HF17, timestamp::max for all posts later (and also all paid)

    curator_payout = sbd_amount(row['curator_payout_value'])
    post['curator_payout_value'] = to_nai(_amount(curator_payout))
    post['total_payout_value'] = to_nai(_amount(row['payout'] - curator_payout))

    post['reward_weight'] = 10000  # ABW: only relevant between HF12 and HF17 and we don't have access to correct value

    post['root_author'] = row['root_author']
    post['root_permlink'] = row['root_permlink']

    post['allow_replies'] = row['allow_replies']
    post['allow_votes'] = row['allow_votes']
    post['allow_curation_rewards'] = row['allow_curation_rewards']

    post['parent_author'] = row['parent_author']
    post['parent_permlink'] = row['parent_permlink_or_category']

    post['beneficiaries'] = row['beneficiaries']
    post['max_accepted_payout'] = to_nai(row['max_accepted_payout'])
    post['percent_hbd'] = row['percent_hbd']
    post['net_votes'] = row['net_votes']

    if paid:
        post['total_vote_weight'] = 0
        post['vote_rshares'] = 0
        post[
            'net_rshares'
        ] = 0  # if row['rshares'] > 0 else row['rshares'] ABW: used to be like this but after HF19 cashouts disappear and all give 0
        post['abs_rshares'] = 0
        post['children_abs_rshares'] = 0
    else:
        post['total_vote_weight'] = row['total_vote_weight']
        post['vote_rshares'] = (row['rshares'] + row['abs_rshares']) // 2  # effectively sum of all positive rshares
        post['net_rshares'] = row['rshares']
        post['abs_rshares'] = row['abs_rshares']
        post[
            'children_abs_rshares'
        ] = 0  # TODO - ABW: I'm not sure about that, it is costly and useless (used to be part of mechanism to determine cashout time)

    return post
