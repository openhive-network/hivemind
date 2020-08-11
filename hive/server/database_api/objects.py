from hive.indexer.votes import Votes
from hive.server.common.helpers import json_date
from hive.utils.normalize import sbd_amount, to_nai

def _amount(amount, asset='HBD'):
    """Return a steem-style amount string given a (numeric, asset-str)."""
    assert asset == 'HBD', 'unhandled asset %s' % asset
    return "%.3f HBD" % amount

def database_post_object(row, truncate_body=0):
    """Given a hive_posts row, create a legacy-style post object."""
    paid = row['is_paidout']

    post = {}
    post['active'] = json_date(row['active'])
    post['author_rewards'] = row['author_rewards']
    post['post_id'] = row['id']
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
    post['children_abs_rshares'] = 0 # TODO
    post['net_rshares'] = row['rshares']

    post['last_payout'] = json_date(row['payout_at'] if paid else None)
    post['cashout_time'] = json_date(None if paid else row['payout_at'])
    post['max_cashout_time'] = json_date(row['max_cashout_time'])
    post['total_payout_value'] = to_nai(_amount(row['payout'] if paid else 0))
    post['curator_payout_value'] = to_nai(_amount(0))

    post['reward_weight'] = row['reward_weight']

    post['root_author'] = row['root_author']
    post['root_permlink'] = row['root_permlink']

    post['allow_replies'] = row['allow_replies']
    post['allow_votes'] = row['allow_votes']
    post['allow_curation_rewards'] = row['allow_curation_rewards']

    if row['depth'] > 0:
        post['parent_author'] = row['parent_author']
        post['parent_permlink'] = row['parent_permlink']
    else:
        post['parent_author'] = ''
        post['parent_permlink'] = row['category']

    post['beneficiaries'] = row['beneficiaries']
    post['max_accepted_payout'] = to_nai(row['max_accepted_payout'])
    post['percent_hbd'] = row['percent_hbd']
    post['abs_rshares'] = row['abs_rshares']
    post['net_votes'] = Votes.get_vote_count(row['author'], row['permlink'])

    if paid:
        curator_payout = sbd_amount(row['curator_payout_value'])
        post['curator_payout_value'] = to_nai(_amount(curator_payout))
        post['total_payout_value'] = to_nai(_amount(row['payout'] - curator_payout))

    post['total_vote_weight'] = Votes.get_total_vote_weight(row['author'], row['permlink'])
    post['vote_rshares'] = Votes.get_total_vote_rshares(row['author'], row['permlink']) 

    return post
