"""Visibility-map coverage of hivemind's large tables, and the watch that vacuums them until it is reached.

Index-only scans read the heap for every page not marked all-visible. A table's
map is emptied when massive sync rewrites it (SET LOGGED, VACUUM FULL), and the
vacuums that follow cannot mark a page while a snapshot older than its rows is
open, which other HAF apps keep open for hours while they sync. Autovacuum may
then not return to the table for a long time, so the watch re-vacuums each large
table once nothing holds the xmin horizon behind its rows any more.
"""

import logging
import threading
from collections.abc import Callable, Sequence
from typing import NamedTuple

import psycopg2

from hive.conf import SCHEMA_NAME
from hive.db.adapter import Db
from hive.indexer.auto_db_disposer import AutoDbDisposer
from hive.signals import can_continue_thread

log = logging.getLogger(__name__)

# Fraction of pages all-visible a large table is vacuumed until.
VISIBILITY_TARGET = 0.95
_LARGE_TABLE_BYTES = 1024**3


class TableCoverage(NamedTuple):
    """A table's size and all-visible pages, as pg_class records them at its last vacuum or analyze."""

    name: str
    pages: int
    all_visible: int
    block_size: int

    @property
    def fraction(self) -> float:
        return self.all_visible / self.pages if self.pages else 1.0

    def __str__(self) -> str:
        return (
            f"{self.name} {100 * self.fraction:.1f}% all-visible "
            f"({self.all_visible}/{self.pages} pages, {self.pages * self.block_size / 1024**3:.1f} GiB)"
        )


class HorizonHolder(NamedTuple):
    """Something holding the xmin horizon behind a target transaction id."""

    holder: str
    xid_age: int
    open_for: str | None

    def __str__(self) -> str:
        opened = f", transaction open {self.open_for}" if self.open_for else ""
        return f"{self.holder}: backend_xmin {self.xid_age} xids old{opened}"


def large_table_coverage(db: Db) -> list[TableCoverage]:
    """Every hivemind table of at least 1 GiB, largest first, with its all-visible pages."""
    rows = db.query_all(
        f"""
SELECT c.relname, c.relpages, c.relallvisible, current_setting('block_size')::INT AS block_size
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = '{SCHEMA_NAME}' AND c.relkind = 'r'
  AND c.relpages::BIGINT * current_setting('block_size')::INT >= {_LARGE_TABLE_BYTES}
ORDER BY c.relpages DESC
"""
    )
    return [
        TableCoverage(
            f"{SCHEMA_NAME}.{row._mapping['relname']}",
            int(row._mapping['relpages']),
            int(row._mapping['relallvisible']),
            int(row._mapping['block_size']),
        )
        for row in rows
    ]


def log_coverage(db: Db, prefix: str) -> list[TableCoverage]:
    """Log each large table's coverage; returns those below VISIBILITY_TARGET."""
    coverage = large_table_coverage(db)
    for table in coverage:
        log.info("%s visibility: %s", prefix, table)
    return [table for table in coverage if table.fraction < VISIBILITY_TARGET]


def horizon_target(db: Db) -> str:
    """The first transaction id not yet assigned: every committed row is older than it."""
    return str(db.query_one("SELECT pg_snapshot_xmax(pg_current_snapshot())::xid"))


# What keeps a vacuum of this database from marking a row written before the
# target all-visible: a backend's snapshot or transaction id (datid is NULL for a
# walsender relaying hot_standby_feedback), a replication slot's xmin, a prepared
# transaction. Autovacuum workers and plain VACUUMs are left out: the horizon
# ignores them (PROC_IN_VACUUM). Without pg_read_all_stats another role's
# `query` reads `<insufficient privilege>`, so such a backend always counts.
_HORIZON_HOLDERS_SQL = """
SELECT holder, xid_age, open_for FROM (
  SELECT 'pid ' || pid || ' (' || coalesce(nullif(application_name, ''), backend_type) || ', '
           || coalesce(state, '?') || ')' AS holder,
         greatest(age(backend_xmin), age(backend_xid)) AS xid_age,
         (now() - xact_start)::TEXT AS open_for
  FROM pg_stat_activity
  WHERE pid <> pg_backend_pid()
    AND (datid IS NULL OR datname = current_database())
    AND backend_type <> 'autovacuum worker'
    AND NOT (state = 'active' AND query ~* '^\\s*vacuum\\M' AND query !~* '\\mfull\\M')
  UNION ALL
  SELECT 'replication slot ' || slot_name, age(xmin), NULL
  FROM pg_replication_slots
  WHERE xmin IS NOT NULL AND (database IS NULL OR database = current_database())
  UNION ALL
  SELECT 'prepared transaction ' || gid, age(transaction), (now() - prepared)::TEXT
  FROM pg_prepared_xacts
  WHERE database = current_database()
) holders
WHERE xid_age > age(%s::xid)
ORDER BY xid_age DESC
"""


def horizon_holders(db: Db, target: str) -> list[HorizonHolder]:
    """What holds the xmin horizon behind `target` (a horizon_target), oldest first."""
    rows = db.query_all_raw(_HORIZON_HOLDERS_SQL, (target,))
    return [HorizonHolder(row[0], int(row[1]), row[2]) for row in rows]


class VisibilityWatch(threading.Thread):
    """Vacuums the large tables below VISIBILITY_TARGET once nothing holds the horizon behind their rows.

    Each round measures coverage (a connection of its own), and returns once every
    large table is at the target. Otherwise it vacuums the tables below it when no
    holder older than the round's target remains, or logs the oldest holder, and
    waits; the wait doubles each round, from `first_delay` up to `max_delay`.
    After `max_vacuums` vacuum rounds that leave a table below the target (churn
    the vacuum cannot keep up with, or a holder it does not see), it stops and
    leaves the table to autovacuum. A failed round is logged and retried. Stops
    on stop() or when the sync shuts down, between statements: stop() does not
    cancel a running vacuum.
    """

    def __init__(
        self,
        db: Db,
        vacuum: Callable[[Sequence[str]], None],
        first_delay: float = 30.0,
        max_delay: float = 300.0,
        max_vacuums: int = 5,
    ) -> None:
        super().__init__(name='visibility_watch', daemon=True)
        self._db = db
        self._vacuum = vacuum
        self._first_delay = first_delay
        self._max_delay = max_delay
        self._max_vacuums = max_vacuums
        self._stopped = threading.Event()

    def stop(self) -> None:
        self._stopped.set()

    def _running(self) -> bool:
        return not self._stopped.is_set() and can_continue_thread()

    def run(self) -> None:
        delay = self._first_delay
        target = None
        vacuums = 0
        while self._running():
            try:
                with AutoDbDisposer(self._db, 'visibility_check') as checker:
                    below = log_coverage(checker.db, "[VISIBILITY]")
                    if not below:
                        log.info("[VISIBILITY] Every large table is at least %d%% all-visible", 100 * VISIBILITY_TARGET)
                        return
                    if vacuums == self._max_vacuums:
                        log.warning(
                            "[VISIBILITY] Still below %d%% all-visible after %d vacuums: %s; leaving them to autovacuum",
                            100 * VISIBILITY_TARGET,
                            vacuums,
                            ', '.join(t.name for t in below),
                        )
                        return
                    if target is None:
                        target = horizon_target(checker.db)
                    holders = horizon_holders(checker.db, target)
                if holders:
                    log.info(
                        "[VISIBILITY] Waiting to vacuum %s: the xmin horizon is held by %d holder(s), the oldest %s",
                        ', '.join(t.name for t in below),
                        len(holders),
                        holders[0],
                    )
                elif self._running():
                    log.info("[VISIBILITY] Vacuuming %s", ', '.join(t.name for t in below))
                    self._vacuum([t.name for t in below])
                    vacuums += 1
                    target = None
            except psycopg2.Error as exc:
                log.warning("[VISIBILITY] Round failed: %s; retrying in %.0fs", exc, delay)
            self._stopped.wait(delay)
            delay = min(delay * 2, self._max_delay)
