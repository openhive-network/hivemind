"""Loading the next massive batch's operations while the current batch is processed."""

import contextlib
import logging
from concurrent.futures import Future, ThreadPoolExecutor
from time import perf_counter

from hive.conf import SCHEMA_NAME
from hive.db.adapter import Db

log = logging.getLogger(__name__)


class OpsPrefetch:
    """Runs prefetch_ops_staging for one block range at a time, on its own connection and thread.

    What it loads is in an UNLOGGED table and its range only in this object, and no
    marker is written: a process that dies mid-prefetch leaves nothing a restart
    reads, and the restart loads every batch, the replayed one included, from HAF.
    """

    def __init__(self, db: Db) -> None:
        self._db = db
        self._executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix='ops_prefetch')
        self._pending: Future[tuple[int, int | None, float]] | None = None

    def start(self, first_block: int, last_block: int) -> None:
        """Start loading first_block..last_block; take() must have collected any earlier load."""
        if self._pending is not None:
            raise RuntimeError('an operations prefetch is already in flight')
        self._pending = self._executor.submit(self._load, first_block, last_block)

    def take(self, first_block: int, last_block: int) -> float | None:
        """Wait for the load in flight; return how long it ran if it covers first_block..last_block, else None.

        A covered range is moved to _ops_staging by load_ops_staging_from_prefetch.
        Re-raises the load's exception.
        """
        if self._pending is None:
            return None
        pending, self._pending = self._pending, None
        loaded_first, loaded_last, seconds = pending.result()
        if loaded_last is not None and loaded_first == first_block and last_block <= loaded_last:
            return seconds
        log.info(
            "Operations prefetch of %d..%s does not cover the batch %d..%d; loading it from HAF",
            loaded_first,
            loaded_last,
            first_block,
            last_block,
        )
        return None

    def close(self) -> None:
        """Wait for the load in flight, discarding it, and close the connection."""
        if self._pending is not None:
            pending, self._pending = self._pending, None
            exc = pending.exception()
            if exc is not None:
                # Nothing reads a discarded prefetch, so its failure loses no data.
                log.warning("Discarding a failed operations prefetch: %s", exc)
        self._executor.shutdown(wait=True)
        self._db.close()

    def _load(self, first_block: int, last_block: int) -> tuple[int, int | None, float]:
        t0 = perf_counter()
        self._db.query_no_return("START TRANSACTION")
        try:
            loaded_last = self._db.query_one(f"SELECT {SCHEMA_NAME}.prefetch_ops_staging({first_block}, {last_block})")
            self._db.query_no_return("COMMIT")
        except Exception:
            with contextlib.suppress(Exception):
                self._db.query_no_return("ROLLBACK")
            raise
        return first_block, loaded_last, perf_counter() - t0
