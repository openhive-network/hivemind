"""Utility stats functions."""

import logging

from hive.conf import SCHEMA_NAME
from hive.indexer.db_adapter_holder import DbAdapterHolder

log = logging.getLogger(__name__)


class Mentions(DbAdapterHolder):
    @classmethod
    def refresh(cls):
        """Deleting too old mentions"""

        log.warning("Deleting too old mentions")

        cls.db.query_no_return(f"SELECT {SCHEMA_NAME}.delete_hive_posts_mentions();")
