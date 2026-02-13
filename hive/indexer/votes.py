"""Votes indexing and processing — now handled by SQL (process_votes_from_staging)."""

from hive.indexer.db_adapter_holder import DbAdapterHolder


class Votes(DbAdapterHolder):
    """Holds DB connection for parallel SQL vote processing."""
