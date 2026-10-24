"""Votes indexing and processing — now handled by SQL (process_votes_from_staging)."""

from hive.db.adapter import Db
from hive.indexer.db_adapter_holder import DbAdapterHolder, DbLiveContextHolder


class Votes(DbAdapterHolder):
    """Holds the DB connections of the votes phase: `db`, plus in massive sync one per further upsert worker."""

    _worker_dbs: list[Db] = []

    @classmethod
    def setup_worker_db_access(cls, shared_db: Db, workers: int) -> None:
        """Open the connections of upsert workers 2..`workers`; none in live sync."""
        if not DbLiveContextHolder.is_live_context():
            cls._worker_dbs = [shared_db.clone(f"Votes_{i}") for i in range(1, workers)]

    @classmethod
    def close_own_db_access(cls) -> None:
        for db in cls._worker_dbs:
            db.close()
        cls._worker_dbs = []
        super().close_own_db_access()

    @classmethod
    def upsert_dbs(cls) -> list[Db]:
        """One connection per upsert worker, `db` first."""
        assert cls.db is not None, 'Votes has no db access; setup_own_db_access was not called'
        return [cls.db, *cls._worker_dbs]
