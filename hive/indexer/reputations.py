""" Reputation update support """

import logging

from hive.conf import SCHEMA_NAME, REPTRACKER_SCHEMA_NAME
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.utils.normalize import escape_characters

log = logging.getLogger(__name__)

CACHED_ITEMS_LIMIT = 200

class Reputations(DbAdapterHolder):
    _from_block= 0
    _to_block= 0

    @classmethod
    def flush(self):
        sql_rep = f"SET SEARCH_PATH TO '{REPTRACKER_SCHEMA_NAME}'; SELECT reptracker_process_blocks('{REPTRACKER_SCHEMA_NAME}', (:from_block, :to_block));"
        self.db.query_no_return(sql_rep, from_block=self._from_block, to_block=self._to_block)

        return self._to_block - self._from_block + 1
