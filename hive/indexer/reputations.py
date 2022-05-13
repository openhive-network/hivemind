""" Reputation update support """

import logging

from hive.conf import SCHEMA_NAME
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.utils.normalize import escape_characters

log = logging.getLogger(__name__)

CACHED_ITEMS_LIMIT = 200


class Reputations(DbAdapterHolder):
    _values = []
    _total_values = 0

    @classmethod
    def process_vote(self, block_num, effective_vote_op):
        tuple = f"('{effective_vote_op['author']}', '{effective_vote_op['voter']}', {escape_characters(effective_vote_op['permlink'])}, {effective_vote_op['rshares']}, {block_num})"
        self._values.append(tuple)

    @classmethod
    def flush(self):
        if not self._values:
            log.info(f"Written total reputation data records: {self._total_values}")
            return 0

        sql = f"""
              INSERT INTO {SCHEMA_NAME}.hive_reputation_data
              (voter_id, author_id, permlink, rshares, block_num)

              SELECT (SELECT ha_v.id FROM {SCHEMA_NAME}.hive_accounts ha_v WHERE ha_v.name = t.voter) as voter_id,
                     (SELECT ha.id FROM {SCHEMA_NAME}.hive_accounts ha WHERE ha.name = t.author) as author_id,
                     t.permlink as permlink, t.rshares, t.block_num
              FROM
              (
              VALUES
                -- author, voter, permlink, rshares, block_num
                {{}}
              ) AS T(author, voter, permlink, rshares, block_num)
              """

        self.beginTx()

        begin = 0
        end = 0
        value_limit = 1000
        size = len(self._values)
        while begin < size:
            end = begin + value_limit
            if end > size:
                end = size

            param = ",".join(self._values[begin:end])
            query = sql.format(param)
            self.db.query_no_return(query)
            begin = end

        self.commitTx()

        n = len(self._values)
        self._values.clear()

        self._total_values = self._total_values + n

        log.info(f"Written total reputation data records: {self._total_values}")

        return n
