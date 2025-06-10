import logging

from hive.conf import SCHEMA_NAME
from hive.indexer.db_adapter_holder import DbAdapterHolder

log = logging.getLogger(__name__)


class PostRshares(DbAdapterHolder):
    """Updates post rshares "after votes update"""

    _ids = set()

    @classmethod
    def add_post_ids(cls, post_ids):
        """Add post ids to update"""
        cls._ids.update(post_ids)

    @classmethod
    def flush(cls):
        """Flush data from cache to db"""
        n = len(cls._ids)
        if cls._ids:
            cls.beginTx()
            sql = f"SELECT * FROM {SCHEMA_NAME}.update_posts_rshares(:post_ids)"
            cls.db.query_no_return(sql, post_ids=list(cls._ids))
            cls.commitTx()
            cls._ids.clear()

        return n
