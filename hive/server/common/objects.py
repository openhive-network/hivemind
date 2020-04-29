from hive.server.common.helpers import json_date
from hive.utils.normalize import sbd_amount, rep_to_raw
import ujson as json

def _amount(amount, asset='HBD'):
    """Return a steem-style amount string given a (numeric, asset-str)."""
    assert asset == 'HBD', 'unhandled asset %s' % asset
    return "%.3f HBD" % amount

def _hydrate_active_votes(vote_csv):
    """Convert minimal CSV representation into steemd-style object."""
    if not vote_csv:
        return []
    votes = []
    for line in vote_csv.split("\n"):
        voter, rshares, percent, reputation = line.split(',')
        votes.append(dict(voter=voter,
                          rshares=rshares,
                          percent=percent,
                          reputation=rep_to_raw(reputation)))
    return votes

async def query_author_map(db, posts):
    """Given a list of posts, returns an author->reputation map."""
    if not posts: return {}
    names = tuple({post['author'] for post in posts})
    sql = "SELECT id, name, reputation FROM hive_accounts WHERE name IN :names"
    return {r['name']: r for r in await db.query_all(sql, names=names)}

def condenser_post_object(row, truncate_body=0):
    """Given a hive_posts_cache row, create a legacy-style post object."""
    paid = row['is_paidout']

    # condenser#3424 mitigation
    if not row['category']:
        row['category'] = 'undefined'

    post = {}
    post['post_id'] = row['post_id']
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
    post['active_votes'] = _hydrate_active_votes(row['votes'])
    #post['author_reputation'] = rep_to_raw(row['author_rep'])

    post['legacy_id'] = row['legacy_id']

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

    post['url'] = row['url']
    post['root_title'] = row['root_title']
    post['beneficiaries'] = row['beneficiaries']
    post['max_accepted_payout'] = row['max_accepted_payout']
    post['percent_steem_dollars'] = row['percent_steem_dollars']

    if paid:
        curator_payout = sbd_amount(row['curator_payout_value'])
        post['curator_payout_value'] = _amount(curator_payout)
        post['total_payout_value'] = _amount(row['payout'] - curator_payout)

    # not used by condenser, but may be useful
    # post['net_votes'] = post['total_votes'] - row['up_votes']

    return post
