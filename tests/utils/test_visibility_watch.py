"""Guard the watch that vacuums hivemind's large tables until their visibility maps cover them.

A vacuum run while an older snapshot is open marks nothing all-visible, so the
watch waits for the snapshot to close, naming it, then vacuums the tables still
below the target and stops once they reach it.
"""

import logging
import threading
from collections.abc import Sequence
from typing import cast
from unittest.mock import MagicMock, patch

import psycopg2
import pytest

from hive.db.adapter import Db
from hive.db.db_state import DbState
from hive.db.visibility import VisibilityWatch

PAGES = 1_000_000
TABLES = ['hive_votes', 'hive_post_data']


class FakeDatabase:
    """A database whose large tables' maps a vacuum fills only while no snapshot older than their rows is open."""

    def __init__(self, open_rounds: int, vacuum_fills: bool = True) -> None:
        self.all_visible = dict.fromkeys(TABLES, 0)
        self.snapshot_open_rounds = open_rounds
        self.vacuum_fills = vacuum_fills
        self.refused_connections: list[Exception] = []
        self.vacuums: list[list[str]] = []
        self.connections = 0

    def clone(self, name: str) -> MagicMock:
        if self.refused_connections:
            raise self.refused_connections.pop()
        self.connections += 1
        conn = MagicMock()
        conn.query_all.side_effect = self._coverage
        conn.query_one.return_value = '1000'
        conn.query_all_raw.side_effect = self._holders
        return conn

    def _coverage(self, sql: str) -> list[MagicMock]:
        assert 'relallvisible' in sql
        return [
            MagicMock(
                _mapping={'relname': t, 'relpages': PAGES, 'relallvisible': self.all_visible[t], 'block_size': 8192}
            )
            for t in TABLES
        ]

    def _holders(self, sql: str, params: tuple[str]) -> list[tuple[str, int, str]]:
        assert params == ('1000',)
        if self.snapshot_open_rounds:
            self.snapshot_open_rounds -= 1
            return [('pid 42 (haf_stats, idle in transaction)', 5000, '02:00:00')]
        return []

    def vacuum(self, tables: Sequence[str]) -> None:
        self.vacuums.append(list(tables))
        if self.vacuum_fills and self.snapshot_open_rounds == 0:
            for table in tables:
                self.all_visible[table.split('.')[1]] = PAGES


def _watch(database: FakeDatabase, first_delay: float = 0.001, max_vacuums: int = 5) -> VisibilityWatch:
    return VisibilityWatch(
        cast(Db, database), database.vacuum, first_delay=first_delay, max_delay=0.004, max_vacuums=max_vacuums
    )


def test_vacuums_once_the_long_snapshot_closes(caplog: pytest.LogCaptureFixture) -> None:
    database = FakeDatabase(open_rounds=3)
    with caplog.at_level(logging.INFO, logger='hive.db.visibility'):
        _watch(database).run()

    assert database.vacuums == [['hivemind_app.hive_votes', 'hivemind_app.hive_post_data']]
    assert database.all_visible == dict.fromkeys(TABLES, PAGES)
    waits = [r.getMessage() for r in caplog.records if 'Waiting to vacuum' in r.getMessage()]
    assert len(waits) == 3
    assert 'pid 42 (haf_stats, idle in transaction): backend_xmin 5000 xids old, transaction open 02:00:00' in waits[0]
    assert 'Every large table is at least 95% all-visible' in caplog.records[-1].getMessage()


def test_tables_already_visible_are_not_vacuumed() -> None:
    database = FakeDatabase(open_rounds=0)
    database.all_visible = {'hive_votes': PAGES, 'hive_post_data': PAGES * 96 // 100}
    _watch(database).run()

    assert database.vacuums == []
    assert database.connections == 1


def test_vacuums_only_the_tables_below_the_target() -> None:
    database = FakeDatabase(open_rounds=0)
    database.all_visible['hive_post_data'] = PAGES
    _watch(database).run()

    assert database.vacuums == [['hivemind_app.hive_votes']]


def test_gives_up_after_max_vacuums_that_do_not_help(caplog: pytest.LogCaptureFixture) -> None:
    database = FakeDatabase(open_rounds=0, vacuum_fills=False)
    with caplog.at_level(logging.WARNING, logger='hive.db.visibility'):
        _watch(database, max_vacuums=2).run()

    assert len(database.vacuums) == 2
    assert 'leaving them to autovacuum' in caplog.records[-1].getMessage()


def test_a_failed_round_is_retried(caplog: pytest.LogCaptureFixture) -> None:
    database = FakeDatabase(open_rounds=0)
    database.refused_connections = [psycopg2.OperationalError('too many clients')]
    with caplog.at_level(logging.WARNING, logger='hive.db.visibility'):
        _watch(database).run()

    assert 'Round failed: too many clients' in caplog.text
    assert database.all_visible == dict.fromkeys(TABLES, PAGES)


def test_stop_ends_the_wait_and_cancels_its_vacuums() -> None:
    database = FakeDatabase(open_rounds=10**6)
    watch = _watch(database, first_delay=3600)
    main_db = MagicMock()
    with (
        patch.object(DbState, 'db', staticmethod(lambda: main_db)),
        patch.object(DbState, '_visibility_watch', watch),
    ):
        watch.start()
        while database.connections == 0:
            threading.Event().wait(0.01)
        DbState.stop_visibility_watch(timeout=5)

    assert not watch.is_alive()
    assert database.vacuums == []
    cancel = main_db.query_no_return.call_args.args[0]
    assert 'pg_cancel_backend' in cancel
    assert "application_name = 'hivemind_visibility_vacuum'" in cancel
