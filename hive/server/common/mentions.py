"""Utility stats functions."""

import logging
from time import perf_counter as perf

from hive.indexer.db_adapter_holder import DbAdapterHolder

log = logging.getLogger(__name__)

class Mentions(DbAdapterHolder):

    @classmethod
    def refresh(cls):
        """Deleting too old mentions"""

        log.warning("Deleting too old mentions")

        cls.db.query_no_return("SELECT delete_hive_posts_mentions();" )
