""" Reputation update support """

import logging

from hive.db.adapter import Db
from hive.db.db_state import DbState
from hive.utils.normalize import escape_characters

log = logging.getLogger(__name__)
DB = Db.instance()

CACHED_ITEMS_LIMIT = 200

class Reputations:
    _queries = []

    @classmethod
    def process_vote(cls, block_num, effective_vote_op):
        cls._queries.append("\nSELECT process_reputation_data({}, '{}', '{}', '{}', {});".format(block_num, effective_vote_op['author'], effective_vote_op['permlink'],
             effective_vote_op['voter'], effective_vote_op['rshares']))

    @classmethod
    def flush(cls):
        query = ""
        i = 0
        items = 0
        for s in cls._queries:
            query = query + str(cls._queries[i]) + ";\n"
            i = i + 1
            items = items + 1
            if items >= CACHED_ITEMS_LIMIT:
                DB.query_no_return(query)
                query = ""
                items = 0

        if items >= CACHED_ITEMS_LIMIT:
            DB.query_no_return(query)
            query = ""
            items = 0

        n = len(cls._queries)
        cls._queries.clear()
        return n

