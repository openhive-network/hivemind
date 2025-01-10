"""Utility stats functions."""

import logging

from hive.conf import SCHEMA_NAME
from hive.indexer.db_adapter_holder import DbAdapterHolder

log = logging.getLogger(__name__)


class PayoutStats:
    @classmethod
    def generate(cls, db, separate_transaction: bool = False):
        """Re-generate payout_stats_view."""

        log.warning(f"Rebuilding payout_stats_view{' in separate transaction' if separate_transaction else ''}")

        if separate_transaction:
            db.query_no_return("START TRANSACTION")

        db.query_no_return(f"REFRESH MATERIALIZED VIEW CONCURRENTLY {SCHEMA_NAME}.payout_stats_view;")

        if separate_transaction:
            db.query_no_return("COMMIT")
