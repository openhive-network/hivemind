"""Follow operations — now handled by SQL (process_follows_for_blocks)."""

from hive.indexer.db_adapter_holder import DbAdapterHolder


class Follow(DbAdapterHolder):
    """Holds DB connection for parallel SQL follow processing."""
