# pylint: disable=missing-docstring,line-too-long
from decimal import Decimal

from hive.utils.post import (
    mentions,
)

POST_1 = {
    "abs_rshares": 0,
    "active": "2017-06-20T15:53:51",
    "active_votes": [
        {
            "percent": 10000,
            "reputation": "468237543674",
            "rshares": 1506388632,
            "time": "2017-06-20T15:53:51",
            "voter": "test-safari",
            "weight": 0,
        },
        {
            "percent": 200,
            "reputation": "492436677632",
            "rshares": 110837437,
            "time": "2017-06-20T16:24:09",
            "voter": "darth-cryptic",
            "weight": 846,
        },
        {
            "percent": 10000,
            "reputation": 2992338,
            "rshares": 621340000,
            "time": "2017-06-20T15:55:15",
            "voter": "test25",
            "weight": 273,
        },
        {
            "percent": 10000,
            "reputation": "60295606918",
            "rshares": 493299375,
            "time": "2017-06-20T15:54:54",
            "voter": "mysqlthrashmetal",
            "weight": 263,
        },
    ],
    "allow_curation_rewards": True,
    "allow_replies": True,
    "allow_votes": True,
    "author": "test-safari",
    "author_reputation": "468237543674",
    "author_rewards": 23,
    "beneficiaries": [],
    "body": "https://pbs.twimg.com/media/DBgNm3jXoAAioyE.jpg",
    "body_length": 0,
    "cashout_time": "1969-12-31T23:59:59",
    "category": "spam",
    "children": 0,
    "children_abs_rshares": 0,
    "created": "2017-06-20T15:53:51",
    "curator_payout_value": "0.000 HBD",
    "depth": 0,
    "id": 4437869,
    "json_metadata": "{\"tags\":[\"spam\"],\"image\":[\"ddd\", \"https://pbs.twimg.com/media/DBgNm3jXoAAioyE.jpg\",\"https://example.com/image.jpg\"],\"app\":\"steemit/0.1\",\"format\":\"markdown\"}",
    "last_payout": "2017-06-27T15:53:51",
    "last_update": "2017-06-20T15:53:51",
    "max_accepted_payout": "1000000.000 HBD",
    "max_cashout_time": "1969-12-31T23:59:59",
    "net_rshares": 0,
    "net_votes": 4,
    "parent_author": "",
    "parent_permlink": "spam",
    "pending_payout_value": "0.000 HBD",
    "percent_hbd": 10000,
    "permlink": "june-spam",
    "reblogged_by": [],
    "replies": [],
    "reblogs": 0,
    "reward_weight": 10000,
    "root_author": "test-safari",
    "root_permlink": "june-spam",
    "root_title": "June Spam",
    "title": "June Spam",
    "total_payout_value": "0.044 HBD",
    "total_pending_payout_value": "0.000 HIVE",
    "total_vote_weight": 0,
    "url": "/spam/@test-safari/june-spam",
    "vote_rshares": 0,
}

POST_2 = {
    "abs_rshares": 0,
    "active": "2017-06-20T15:53:51",
    "active_votes": [],
    "allow_curation_rewards": True,
    "allow_replies": True,
    "allow_votes": True,
    "author": "test-safari",
    "author_reputation": "468237543674",
    "author_rewards": 23,
    "beneficiaries": [],
    "body": "https://pbs.twimg.com/media/DBgNm3jXoAAioyE.jpg",
    "body_length": 0,
    "cashout_time": "1969-12-31T23:59:59",
    "category": "steemit",
    "children": 0,
    "children_abs_rshares": 0,
    "created": "2017-06-20T15:53:51",
    "curator_payout_value": "0.000 HBD",
    "depth": 0,
    "id": 4437869,
    "json_metadata": "{\"tags\":[\"steemit\",\"steem\",\"\",\"abc\",\"bcd\",\"cde\"]}",
    "last_payout": "2017-06-27T15:53:51",
    "last_update": "2017-06-20T15:53:51",
    "max_accepted_payout": "1000000.000 HBD",
    "max_cashout_time": "1969-12-31T23:59:59",
    "net_rshares": 0,
    "net_votes": 4,
    "parent_author": "",
    "parent_permlink": "spam",
    "pending_payout_value": "0.000 HBD",
    "percent_hbd": 10000,
    "permlink": "june-spam",
        "reblogged_by": [],
    "replies": [],
    "reblogs": 0,
    "reward_weight": 10000,
    "root_author": "test-safari",
    "root_permlink": "june-spam",
    "root_title": "June Spam",
    "title": "June Spam",
    "total_payout_value": "0.044 HBD",
    "total_pending_payout_value": "0.000 HIVE",
    "total_vote_weight": 0,
    "url": "/spam/@test-safari/june-spam",
    "vote_rshares": 0,
}


def test_mentions():
    # pylint: disable=invalid-name
    m = mentions
    assert m('Hi @abc, meet @bob') == {'abc', 'bob'}
    assert m('Hi @abc, meet @abc') == {'abc'}
    assert not m('')
    assert not m('@')
    assert not m('steemit.com/@apple')
    assert not m('joe@apple.com')
    assert m('@longestokaccount') == {'longestokaccount'}
    assert not m('@longestokaccountx')
    assert m('@abc- @-foo @bar.') == {'abc', 'bar'}
    assert m('_[@foo](https://steemit.com/@foo)_') == {'foo'}
