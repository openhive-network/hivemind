"""Time hivemind's connections spend waiting on locks, sampled from pg_stat_activity."""

import logging
import threading
from collections import defaultdict
from collections.abc import Iterable
from time import monotonic

import psycopg2

from hive.db.adapter import Db

log = logging.getLogger(__name__)


def connection_name(db: Db) -> str:
    """The application_name `db` connects with (Db._connect)."""
    return f'hivemind_{db.name}'


class LockWaitSampler:
    """Samples, on a thread and connection of its own, which `hivemind_*` connections of the database wait on a lock.

    Each sample adds the time since the previous one to the total of every connection it finds
    waiting (wait_event_type 'Lock': row, transaction, relation and other heavyweight locks), so a
    total is accurate to about one sampling interval per wait.
    """

    _SQL = (
        "SELECT application_name FROM pg_stat_activity "
        "WHERE wait_event_type = 'Lock' AND datname = current_database() AND application_name LIKE 'hivemind\\_%'"
    )

    def __init__(self, db: Db, interval: float = 0.1) -> None:
        self._db = db
        self._interval = interval
        self._totals: defaultdict[str, float] = defaultdict(float)
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, name='lock_wait_sampler', daemon=True)

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        """End the sampling and close the connection; the totals stay readable."""
        self._stop.set()
        self._thread.join()
        self._db.close()

    def total(self, names: Iterable[str]) -> float:
        """Seconds the connections of these application names have waited on locks so far, together."""
        with self._lock:
            return sum(self._totals.get(name, 0.0) for name in set(names))

    def _run(self) -> None:
        last = monotonic()
        while not self._stop.wait(self._interval):
            try:
                waiting = self._db.query_col(self._SQL)
            except psycopg2.Error:
                log.warning("Lock wait sampling stopped: its query failed", exc_info=True)
                return
            now = monotonic()
            with self._lock:
                for name in waiting:
                    self._totals[name] += now - last
            last = now
