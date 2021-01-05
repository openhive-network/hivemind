"""Utility stats functions."""

import logging

from hive.indexer.db_adapter_holder import DbAdapterHolder

log = logging.getLogger(__name__)

class PayoutStats(DbAdapterHolder):

    @classmethod
    def generate(cls):
        """Re-generate payout_stats_view."""

        log.warning("Rebuilding payout_stats_view")

        cls.db.query_no_return("REFRESH MATERIALIZED VIEW CONCURRENTLY payout_stats_view;" )
