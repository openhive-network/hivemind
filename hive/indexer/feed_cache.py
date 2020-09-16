"""Maintains feed cache (blogs + reblogs)"""

import logging
from hive.db.adapter import Db
from hive.indexer.db_adapter_holder import DbAdapterHolder

log = logging.getLogger(__name__)

DB = Db.instance()

class FeedCache(DbAdapterHolder):
    """Maintains `hive_feed_cache`, which merges posts and reports.

    The feed cache allows for efficient querying of posts + reblogs,
    savings us from expensive queries. Effectively a materialized view.
    """
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
