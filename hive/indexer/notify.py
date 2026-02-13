"""Handle notifications — lastread and notification flushing now handled by SQL."""

from hive.indexer.db_adapter_holder import DbAdapterHolder


class Notify(DbAdapterHolder):
    """Holds DB connection for parallel SQL notification processing."""
