"""Payouts processing — handled by SQL (process_payouts_from_staging)."""

from hive.indexer.db_adapter_holder import PartitionedDbAdapterHolder


class Payouts(PartitionedDbAdapterHolder):
    """Holds the DB connections of the payouts phase: `db`, plus in massive sync one per further partition."""
