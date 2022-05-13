"""Utility stats functions."""

import logging

from hive.conf import SCHEMA_NAME
from hive.indexer.db_adapter_holder import DbAdapterHolder

log = logging.getLogger(__name__)


class PayoutStats(DbAdapterHolder):
    @classmethod
    def generate(cls):
        """Re-generate payout_stats_view."""

        log.warning("Rebuilding payout_stats_view")

        cls.db.query_no_return(f"REFRESH MATERIALIZED VIEW CONCURRENTLY {SCHEMA_NAME}.payout_stats_view;")
