"""Guard the thread pool of finalization's tasks and the vacuums run in it.

A failed task leaves no other task running behind it, vacuums run at most
DbState.vacuum_workers at a time, and a vacuum whose connection is refused is
retried and then skipped instead of failing finalization.
"""

import threading
import time
from collections.abc import Callable
from unittest.mock import MagicMock, patch

import psycopg2
import pytest

from hive.db.db_state import DbState

TABLES = [f'hivemind_app.table_{i}' for i in range(12)]


def test_failed_task_leaves_no_task_running() -> None:
    running = set()
    started = []
    lock = threading.Lock()
    slow_started = threading.Event()

    def slow(name: str) -> None:
        with lock:
            running.add(name)
            started.append(name)
        slow_started.set()
        time.sleep(0.3)
        with lock:
            running.discard(name)

    def failing() -> None:
        slow_started.wait(5)
        raise RuntimeError('boom')

    methods: list[tuple[str, Callable[..., None], list[str]]] = [('slow', slow, ['slow']), ('failing', failing, [])]
    methods += [(f'queued_{i}', slow, [f'queued_{i}']) for i in range(5)]

    with pytest.raises(RuntimeError, match='boom'):
        DbState.process_tasks_in_threads('test', methods, max_workers=2)

    assert running == set()
    # The worker freed by the failure may take one queued task before the pool is shut
    # down; the rest are cancelled before starting.
    assert started[0] == 'slow'
    assert len(started) <= 2


def test_vacuums_run_at_most_vacuum_workers_at_a_time() -> None:
    lock = threading.Lock()
    current = 0
    peak = 0
    statements = []

    def on_vacuum(sql: str) -> None:
        nonlocal current, peak
        with lock:
            current += 1
            peak = max(peak, current)
            statements.append(sql)
        time.sleep(0.05)
        with lock:
            current -= 1

    db = MagicMock()
    db.clone.return_value.query_no_return_autocommit.side_effect = on_vacuum
    with (
        patch.object(DbState, 'db', staticmethod(lambda: db)),
        patch.object(DbState, 'vacuum_workers', 3),
    ):
        DbState.vacuum_tables_in_threads(plain=TABLES[:6], frozen=TABLES[6:])

    assert peak == 3
    assert sorted(statements) == sorted(
        [f'VACUUM (VERBOSE, ANALYZE) {t}' for t in TABLES[:6]]
        + [f'VACUUM (FREEZE, VERBOSE, ANALYZE) {t}' for t in TABLES[6:]]
    )


def _connection(statements: list[str]) -> MagicMock:
    connection = MagicMock()
    connection.query_no_return_autocommit.side_effect = statements.append
    return connection


def test_refused_vacuum_connection_is_retried() -> None:
    statements: list[str] = []
    connection = _connection(statements)
    refused = psycopg2.OperationalError('FATAL:  sorry, too many clients already')
    db = MagicMock()
    db.clone.side_effect = [refused, refused, connection]

    with (
        patch.object(DbState, 'db', staticmethod(lambda: db)),
        patch('hive.db.db_state.sleep') as sleep,
    ):
        DbState.vacuum_tables_in_threads(frozen=TABLES[:1])

    assert statements == [f'VACUUM (FREEZE, VERBOSE, ANALYZE) {TABLES[0]}']
    assert sleep.call_count == 2
    connection.close.assert_called_once()


def test_vacuum_without_connection_is_skipped() -> None:
    statements: list[str] = []
    refused = psycopg2.OperationalError('FATAL:  remaining connection slots are reserved for superusers')
    db = MagicMock()
    db.clone.side_effect = [refused] * DbState._VACUUM_CONNECT_ATTEMPTS + [_connection(statements)]

    with (
        patch.object(DbState, 'db', staticmethod(lambda: db)),
        patch.object(DbState, 'vacuum_workers', 1),
        patch('hive.db.db_state.sleep'),
    ):
        DbState.vacuum_tables_in_threads(plain=TABLES[:2])

    # The first table's vacuum gives up after its attempts; the next one still runs.
    assert statements == [f'VACUUM (VERBOSE, ANALYZE) {TABLES[1]}']
