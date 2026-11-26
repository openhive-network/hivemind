import logging

log = logging.getLogger(__name__)

from hive.db.adapter import Db  # noqa: E402


class DbLiveContextHolder:
    _live_context: bool | None = None

    @classmethod
    def set_live_context(cls, live_context):
        cls._live_context = live_context

    @classmethod
    def is_live_context(cls) -> bool | None:
        return cls._live_context


class DbAdapterHolder:
    db: Db | None = None
    _block_processing_thread_sync_db = None
    _stage_b_processing_db: Db | None = None

    _inside_sync_tx = False

    @classmethod
    def setup_own_db_access(cls, sharedDb: Db, name: str) -> None:
        if DbLiveContextHolder.is_live_context():
            cls.db = sharedDb
        else:
            cls.db = sharedDb.clone(name)

    @classmethod
    def close_own_db_access(cls) -> None:
        if cls.db is not None:
            cls.db.close()
            cls.db = None

    @classmethod
    def sync_tx_active(cls):
        return cls._inside_sync_tx

    @classmethod
    def beginTx(cls):
        if not DbLiveContextHolder.is_live_context():
            cls.db.query("START TRANSACTION")
            cls._inside_sync_tx = True

    @classmethod
    def commitTx(cls):
        if not DbLiveContextHolder.is_live_context():
            cls.db.query("COMMIT")
            cls._inside_sync_tx = False

    @staticmethod
    def common_block_processing_db() -> Db:
        """Get the shared instance."""
        if DbAdapterHolder._block_processing_thread_sync_db is not None:
            return DbAdapterHolder._block_processing_thread_sync_db
        return Db.instance()

    @staticmethod
    def open_common_blocks_in_background_processing_db():
        """Get the shared instance."""
        assert DbAdapterHolder._block_processing_thread_sync_db is None, 'massive instance already opened'
        DbAdapterHolder._block_processing_thread_sync_db = Db.instance().clone("massive_instance")

    @staticmethod
    def close_common_blocks_in_background_processing_db():
        """Get the shared instance."""
        if DbAdapterHolder._block_processing_thread_sync_db is not None:
            DbAdapterHolder._block_processing_thread_sync_db.close()
            DbAdapterHolder._block_processing_thread_sync_db = None

    @staticmethod
    def stage_b_processing_db() -> Db:
        """The connection of pipelined massive sync's Stage B, the shared block processing one when it has none."""
        if DbAdapterHolder._stage_b_processing_db is not None:
            return DbAdapterHolder._stage_b_processing_db
        return DbAdapterHolder.common_block_processing_db()

    @staticmethod
    def open_stage_b_processing_db() -> None:
        assert DbAdapterHolder._stage_b_processing_db is None, 'stage B instance already opened'
        DbAdapterHolder._stage_b_processing_db = Db.instance().clone("stage_b_instance")

    @staticmethod
    def close_stage_b_processing_db() -> None:
        if DbAdapterHolder._stage_b_processing_db is not None:
            DbAdapterHolder._stage_b_processing_db.close()
            DbAdapterHolder._stage_b_processing_db = None


class PartitionedDbAdapterHolder(DbAdapterHolder):
    """A DbAdapterHolder whose massive-sync phase runs in partitions: `db`, plus in massive sync one connection per further partition."""

    _worker_dbs: list[Db] = []

    @classmethod
    def setup_worker_db_access(cls, shared_db: Db, workers: int) -> None:
        """Open the connections of partitions 2..`workers`; none in live sync."""
        if not DbLiveContextHolder.is_live_context():
            cls._worker_dbs = [shared_db.clone(f"{cls.__name__}_{i}") for i in range(1, workers)]

    @classmethod
    def close_own_db_access(cls) -> None:
        for db in cls._worker_dbs:
            db.close()
        cls._worker_dbs = []
        super().close_own_db_access()

    @classmethod
    def partition_dbs(cls) -> list[Db]:
        """One connection per partition, `db` first; raises RuntimeError before setup_own_db_access."""
        if cls.db is None:
            raise RuntimeError(f'{cls.__name__} has no db access; setup_own_db_access was not called')
        return [cls.db, *cls._worker_dbs]
