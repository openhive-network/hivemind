"""Reblog operations — now handled by SQL (process_reblogs_from_staging)."""

from hive.indexer.db_adapter_holder import DbAdapterHolder


class Reblog(DbAdapterHolder):
    """Holds DB connection for parallel SQL reblog processing."""
