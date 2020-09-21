"""Utility stats functions."""

import logging
from time import perf_counter as perf

log = logging.getLogger(__name__)

class PayoutStats:

    @classmethod
    def generate(self, db ):
        """Re-generate payout_stats_view."""

        log.warning("Rebuilding payout_stats_view")

        db.query_no_return("REFRESH MATERIALIZED VIEW CONCURRENTLY payout_stats_view;" )
