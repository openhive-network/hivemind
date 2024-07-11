"""Process payment ops used for promoted posts."""

import logging

from hive.conf import SCHEMA_NAME
from hive.db.adapter import Db
from hive.indexer.accounts import Accounts
from hive.utils.normalize import parse_amount

log = logging.getLogger(__name__)

class Payments:
    """Handles payments to update post promotion values."""

    # pylint: disable=too-few-public-methods

    @classmethod
    def op_transfer(cls, op, tx_idx, num, date):
        """Process raw transfer op; apply balance if valid post promote."""
        result = cls._validated(op, tx_idx, num, date)
        if not result:
            return

        record, author_id, permlink = result

        # add payment record and return post id
        sql = f"""
INSERT INTO {SCHEMA_NAME}.hive_payments(block_num, tx_idx, post_id, from_account, to_account, amount, token) SELECT
  bn, tx, hp.id, fa, ta, am, tkn
FROM
( 
  SELECT bn, tx, hpd.id, auth_id, fa, ta, am, tkn
  FROM (VALUES (:_block_num, :_tx_idx, :_permlink, :_author_id , :_from_account , :_to_account , :_amount, :_token)) 
  AS v(bn, tx, perm, auth_id, fa, ta, am, tkn) 
  JOIN {SCHEMA_NAME}.hive_permlink_data hpd
  ON v.perm = hpd.permlink
) as vv(bn, tx, hpd_id, auth_id, fa, ta, am, tkn )
JOIN {SCHEMA_NAME}.hive_posts hp
ON hp.author_id=vv.auth_id AND hp.permlink_id=vv.hpd_id
RETURNING post_id
"""

        post_id = Db.data_sync_instance().query_one(
            sql,
            _block_num=record['block_num'],
            _tx_idx=record['tx_idx'],
            _permlink=permlink,
            _author_id=author_id,
            _from_account=record['from_account'],
            _to_account=record['to_account'],
            _amount=record['amount'],
            _token=record['token'],
        )

        amount = record['amount']
        if not isinstance(amount, float):
            amount = float(amount)

        if amount != 0.0 and post_id is not None:
            # update post record
            sql = f"UPDATE {SCHEMA_NAME}.hive_posts SET promoted = promoted + :val WHERE id = :id"
            Db.data_sync_instance().query(sql, val=amount, id=post_id)

    @classmethod
    def _validated(cls, op, tx_idx, num, date):
        """Validate and normalize the transfer op."""
        # pylint: disable=unused-argument
        if op['to'] != 'null':
            return  # only care about payments to null

        amount, token = parse_amount(op['amount'])
        if token != 'HBD':
            return  # only care about HBD payments

        url = op['memo']
        if not cls._validate_url(url):
            log.debug("invalid url: %s", url)
            return  # invalid url

        author, permlink = cls._split_url(url)
        author_id = Accounts.get_id_noexept(author)
        if not author_id:
            return

        return [
            {
                'id': None,
                'block_num': num,
                'tx_idx': tx_idx,
                'from_account': Accounts.get_id(op['from']),
                'to_account': Accounts.get_id(op['to']),
                'amount': amount,
                'token': token,
            },
            author_id,
            permlink,
        ]

    @staticmethod
    def _validate_url(url):
        """Validate if `url` is in proper `@account/permlink` format."""
        if not url or url.count('/') != 1 or url[0] != '@':
            return False
        return True

    @staticmethod
    def _split_url(url):
        """Split a `@account/permlink` string into (account, permlink)."""
        return url[1:].split('/')
