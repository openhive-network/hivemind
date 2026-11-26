"""Votes indexing and processing — now handled by SQL (process_votes_from_staging)."""

from hive.db.adapter import Db
from hive.indexer.db_adapter_holder import PartitionedDbAdapterHolder


class Votes(PartitionedDbAdapterHolder):
    """Holds the DB connections of the votes phase: `db`, plus in massive sync one per further upsert worker."""

    @classmethod
    def upsert_dbs(cls) -> list[Db]:
        """One connection per upsert worker, `db` first."""
        return cls.partition_dbs()
