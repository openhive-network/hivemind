"""Maintains feed cache (blogs + reblogs)"""

import logging
import time
from hive.db.adapter import Db
from hive.db.db_state import DbState
from hive.indexer.db_adapter_holder import DbAdapterHolder

log = logging.getLogger(__name__)

DB = Db.instance()

class FeedCache(DbAdapterHolder):
    """Maintains `hive_feed_cache`, which merges posts and reports.

    The feed cache allows for efficient querying of posts + reblogs,
    savings us from expensive queries. Effectively a materialized view.
    """
    _feed_cache_items = []

    @classmethod
    def flush(cls):
        query_prefix = """
            INSERT INTO hive_feed_cache (account_id, post_id, created_at, block_num)
            VALUES
        """
        query_suffix = """
            ON CONFLICT ON CONSTRAINT hive_feed_cache_pk DO NOTHING
        """
        values = []
        limit = 1000
        count = 0
        n = len(cls._feed_cache_items)
        cls.beginTx()
        for feed_cache_item in cls._feed_cache_items:
            if count < limit:
                values.append("({}, {}, '{}', {})".format(feed_cache_item[0], feed_cache_item[1],
                                                          feed_cache_item[2], feed_cache_item[3]))
                count = count + 1
            else:
                query = query_prefix + ",".join(values)
                query += query_suffix
                cls.db.query(query)
                values.clear()
                values.append("({}, {}, '{}', {})".format(feed_cache_item[0], feed_cache_item[1], 
                                                          feed_cache_item[2], feed_cache_item[3]))
                count = 1

        if len(values) > 0:
            query = query_prefix + ",".join(values)
            query += query_suffix
            cls.db.query(query)
        cls._feed_cache_items.clear()
        cls.commitTx()
        return n

    @classmethod
    def insert(cls, post_id, account_id, created_at, block_num):
        """Inserts a [re-]post by an account into feed."""
        cls._feed_cache_items.append((account_id, post_id, created_at, block_num))

    @classmethod
    def delete(cls, post_id, account_id=None):
        """Remove a post from feed cache.

        If `account_id` is specified, we remove a single entry (e.g. a
        singular un-reblog). Otherwise, we remove all instances of the
        post (e.g. a post was deleted; its entry and all reblogs need
        to be removed.
        """
        sql = "DELETE FROM hive_feed_cache WHERE post_id = :id"
        if account_id:
            sql = sql + " AND account_id = :account_id"
        DB.query(sql, account_id=account_id, id=post_id)
