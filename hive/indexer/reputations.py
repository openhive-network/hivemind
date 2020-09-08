""" Reputation update support """

import logging
from hive.indexer.db_adapter_holder import DbAdapterHolder

log = logging.getLogger(__name__)

CACHED_ITEMS_LIMIT = 200

class Reputations(DbAdapterHolder):
    _queries = []

    @classmethod
    def process_vote(self, block_num, effective_vote_op):
        return 
        self._queries.append("\nSELECT process_reputation_data({}, '{}', '{}', '{}', {});".format(block_num, effective_vote_op['author'], effective_vote_op['permlink'],
             effective_vote_op['voter'], effective_vote_op['rshares']))

    @classmethod
    def flush(self):
        if not self._queries:
            return 0

        self.beginTx()

        query = ""
        i = 0
        items = 0
        for s in self._queries:
            query = query + str(self._queries[i]) + ";\n"
            i = i + 1
            items = items + 1
            if items >= CACHED_ITEMS_LIMIT:
                self.db.query_no_return(query)
                query = ""
                items = 0

        if items >= CACHED_ITEMS_LIMIT:
            self.db.query_no_return(query)
            query = ""
            items = 0

        n = len(self._queries)
        self._queries.clear()

        self.commitTx()
        return n

