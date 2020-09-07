""" Reputation update support """

import logging
log = logging.getLogger(__name__)

CACHED_ITEMS_LIMIT = 200

class Reputations:
    _queries = []
    _db = None

    def __init__(self, database):
        log.info("Cloning database...")
        self._db = database.clone()
        assert self._db is not None, "Database not cloned"
        log.info("Database object at: {}".format(self._db))

    def process_vote(self, block_num, effective_vote_op):
        self._queries.append("\nSELECT process_reputation_data({}, '{}', '{}', '{}', {});".format(block_num, effective_vote_op['author'], effective_vote_op['permlink'],
             effective_vote_op['voter'], effective_vote_op['rshares']))

    def flush(self):
        query = ""
        i = 0
        items = 0
        for s in self._queries:
            query = query + str(self._queries[i]) + ";\n"
            i = i + 1
            items = items + 1
            if items >= CACHED_ITEMS_LIMIT:
                self._db.query_no_return(query)
                query = ""
                items = 0

        if items >= CACHED_ITEMS_LIMIT:
            self._db.query_no_return(query)
            query = ""
            items = 0

        n = len(self._queries)
        self._queries.clear()
        return n

