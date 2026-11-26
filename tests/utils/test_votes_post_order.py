"""Guard the rewrite of hive_votes in post order at an initial sync's index restore.

In one transaction, hive_votes is sorted into an UNLOGGED copy by a parallel query,
copied back, its registered (post_id, voter_id) index is built from its registered
command and marked as the clustering index; its other indexes are restored after
that, and the table is vacuumed once a BM25 build running beside it has ended. A
rerun that finds the index already marked, and every restore outside an initial
sync, leaves the table as it is. An interruption before the commit leaves no mark,
so the restart rewrites the table again.
"""

import threading
import time
from collections.abc import Callable, Iterator, Sequence
from contextlib import contextmanager
from typing import Any
from unittest.mock import MagicMock, patch

import pytest

from hive.db.db_state import DbState

_COMMAND = 'create index if not exists hive_votes_post_id_voter_id_idx on hivemind_app.hive_votes (post_id, voter_id)'
_LOCK = 'LOCK TABLE hivemind_app.hive_votes IN ACCESS EXCLUSIVE MODE'
_SORT = (
    'CREATE UNLOGGED TABLE hivemind_app.__hive_votes_sorted AS '
    'SELECT * FROM hivemind_app.hive_votes ORDER BY post_id, voter_id'
)
_COPY_BACK = "SELECT * FROM hivemind_app.copy_back_hive_votes('hivemind_app.__hive_votes_sorted')"
_MARK = 'ALTER TABLE hivemind_app.hive_votes CLUSTER ON hive_votes_post_id_voter_id_idx'
_DROP_COPY = 'DROP TABLE hivemind_app.__hive_votes_sorted'
_VACUUM = 'VACUUM (FREEZE, ANALYZE) hivemind_app.hive_votes'
_RESTORE_HIVE_VOTES = "SELECT hive.app_restore_indexes('hivemind_app', 'hivemind_app.hive_votes')"
_REWRITE = ['START TRANSACTION', _LOCK, _SORT, _COPY_BACK, _COMMAND, _MARK, _DROP_COPY, 'COMMIT']


class _ProcessExit(BaseException):
    """The process ending mid-rewrite: no code of the rewrite catches it."""


class _Database:
    """A connection recording its statements, whose registration row carries the clustering mark it keeps.

    The mark becomes durable only when the transaction that set it commits.
    """

    def __init__(self, registered: bool = True, clustered: bool = False) -> None:
        self.statements: list[str] = []
        self.registered = registered
        self.clustered = clustered
        self.exit_at: str | None = None
        self._marked_in_transaction = False
        self._lock = threading.Lock()

    def clone(self, name: str) -> _Database:
        return self

    def close(self) -> None:
        pass

    def _record(self, sql: str) -> None:
        with self._lock:
            self.statements.append(sql)
        if sql == self.exit_at:
            raise _ProcessExit

    def query_no_return(self, sql: str, **kwargs: Any) -> None:
        self._record(sql)
        if sql == _MARK:
            self._marked_in_transaction = True
        if sql == 'COMMIT' and self._marked_in_transaction:
            self.clustered = True
        if sql in ('COMMIT', 'ROLLBACK'):
            self._marked_in_transaction = False

    query_no_return_autocommit = query_no_return

    def query_col(self, sql: str, **kwargs: Any) -> list[Any]:
        return []

    def query_all(self, sql: str) -> list[Any]:
        assert 'copy_back_hive_votes' in sql, sql
        self._record(sql)
        return [MagicMock(_mapping={'copy_seconds': 1.0, 'rebuild_seconds': 2.0})]

    def query_row(self, sql: str) -> Any:
        if 'hafd.indexes_constraints' in sql:
            self._record('registration lookup')
            if not self.registered:
                return None
            return MagicMock(_mapping={'command': _COMMAND, 'clustered': self.clustered})
        assert 'relallvisible' in sql, sql
        return MagicMock(_mapping={'relpages': 100, 'relallvisible': 100})


def _run_in_order(
    info: str, methods: Sequence[tuple[str, Callable[..., None], list[Any]]], max_workers: int | None = None
) -> None:
    for _description, method, args in methods:
        method(*args)


@contextmanager
def _db_state(
    database: _Database,
    initial_sync: bool = True,
    run_tasks: Callable[..., None] = _run_in_order,
) -> Iterator[None]:
    with (
        patch.object(DbState, 'db', staticmethod(lambda: database)),
        patch.object(DbState, 'process_tasks_in_threads', staticmethod(run_tasks)),
        patch.object(
            DbState,
            '_execute_query_with_modified_work_mem',
            staticmethod(lambda db, sql, **kwargs: db.query_no_return(sql)),
        ),
        patch.multiple(
            DbState,
            _initial_sync=initial_sync,
            _indexes_were_enabled=False,
            _indexes_were_disabled=True,
            _deferred_index_tables=[],
        ),
        patch('hive.db.db_state.AutoDbDisposer', _Disposer),
        patch('hive.db.schema.ensure_tables_logged', lambda *a: None),
    ):
        yield


class _Disposer:
    def __init__(self, db: _Database, name: str) -> None:
        self.db = db

    def __enter__(self) -> _Disposer:
        return self

    def __exit__(self, *exc: object) -> None:
        pass


def _rewrite_statements(statements: list[str]) -> list[str]:
    return [sql for sql in statements if sql in _REWRITE]


def test_initial_sync_rewrites_hive_votes_in_one_transaction_before_restoring_its_indexes() -> None:
    database = _Database()
    with _db_state(database):
        DbState.ensure_indexes_are_enabled()

    statements = database.statements
    assert _rewrite_statements(statements) == _REWRITE
    assert 'SET LOCAL enable_indexscan = off' in statements
    assert f'SET LOCAL max_parallel_workers_per_gather = {DbState.finalization_workers}' in statements
    order = [statements.index(sql) for sql in ('COMMIT', _RESTORE_HIVE_VOTES, _VACUUM)]
    assert order == sorted(order)
    assert database.clustered


def test_rerun_after_the_rewrite_does_not_rewrite_again() -> None:
    database = _Database(clustered=True)
    with _db_state(database):
        DbState.ensure_indexes_are_enabled()

    assert 'registration lookup' in database.statements
    assert _rewrite_statements(database.statements) == []
    assert _VACUUM not in database.statements
    assert _RESTORE_HIVE_VOTES in database.statements


def test_unregistered_index_leaves_hive_votes_unordered_but_restored() -> None:
    database = _Database(registered=False)
    with _db_state(database):
        DbState.ensure_indexes_are_enabled()

    assert _rewrite_statements(database.statements) == []
    assert _RESTORE_HIVE_VOTES in database.statements


def test_restore_outside_an_initial_sync_keeps_the_table() -> None:
    database = _Database()
    with _db_state(database, initial_sync=False):
        DbState.ensure_indexes_are_enabled(build_search_index=True)

    assert 'registration lookup' not in database.statements
    assert _rewrite_statements(database.statements) == []
    assert _RESTORE_HIVE_VOTES in database.statements


@pytest.mark.parametrize('exit_at', [_SORT, _COPY_BACK, _MARK, _DROP_COPY, 'COMMIT'])
def test_rewrite_interrupted_before_its_commit_is_redone_on_restart(exit_at: str) -> None:
    uninterrupted = _Database()
    with _db_state(uninterrupted):
        DbState.ensure_indexes_are_enabled()

    database = _Database()
    database.exit_at = exit_at
    with _db_state(database), pytest.raises(_ProcessExit):
        DbState.ensure_indexes_are_enabled()
    assert database.statements[-1] == 'ROLLBACK'
    assert not database.clustered

    database.exit_at = None
    database.statements = []
    with _db_state(database):
        DbState.ensure_indexes_are_enabled()

    assert database.statements == uninterrupted.statements
    assert database.clustered


def test_rewrite_interrupted_after_its_commit_is_not_redone_on_restart() -> None:
    database = _Database()
    database.exit_at = _RESTORE_HIVE_VOTES
    with _db_state(database), pytest.raises(_ProcessExit):
        DbState.ensure_indexes_are_enabled()
    assert database.clustered

    database.exit_at = None
    database.statements = []
    with _db_state(database):
        DbState.ensure_indexes_are_enabled()

    assert _rewrite_statements(database.statements) == []
    assert _RESTORE_HIVE_VOTES in database.statements


def _run_in_threads(
    info: str, methods: Sequence[tuple[str, Callable[..., None], list[Any]]], max_workers: int | None = None
) -> None:
    threads = [threading.Thread(target=method, args=args) for _description, method, args in methods]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()


def test_bm25_build_runs_beside_the_rewrite_and_the_vacuum_waits_for_it() -> None:
    database = _Database()
    build_started = threading.Event()

    def build_bm25(db: Any) -> None:
        build_started.set()
        time.sleep(0.3)
        database.query_no_return('bm25 built')

    with (
        _db_state(database, run_tasks=_run_in_threads),
        patch.object(DbState, '_restore_bm25_index', staticmethod(build_bm25)),
    ):
        DbState.ensure_indexes_are_enabled(defer_to_finalization=True, build_search_index=True)

    statements = database.statements
    assert build_started.is_set()
    assert statements.index('COMMIT') < statements.index('bm25 built') < statements.index(_VACUUM)


def test_bm25_build_waits_for_finalization_when_massive_batches_follow_the_restore() -> None:
    database = _Database()
    build = MagicMock()
    with _db_state(database), patch.object(DbState, '_restore_bm25_index', build):
        DbState.ensure_indexes_are_enabled(defer_to_finalization=True)

    build.assert_not_called()
    assert _VACUUM in database.statements
