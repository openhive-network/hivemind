"""Guard the rewrite of hive_votes in post order at an initial sync's index restore.

The registered (post_id, voter_id) index is built from its registered command,
hive_votes is clustered on it and vacuumed, and only then are its other indexes
restored. A rerun that finds the index already clustered, and every restore
outside an initial sync, leaves the table as it is. CLUSTER sets the mark when it
commits, so a restart after an interruption before that clusters the table again,
and one after it does not. A BM25 build running beside the rewrite does not hold
the vacuum back.
"""

import threading
from collections.abc import Callable, Iterator, Sequence
from contextlib import contextmanager
from typing import Any
from unittest.mock import MagicMock, patch

import pytest

from hive.db.db_state import DbState

_COMMAND = 'create index if not exists hive_votes_post_id_voter_id_idx on hivemind_app.hive_votes (post_id, voter_id)'
_CLUSTER = 'CLUSTER hivemind_app.hive_votes USING hive_votes_post_id_voter_id_idx'
_VACUUM = 'VACUUM (FREEZE, ANALYZE) hivemind_app.hive_votes'
_RESTORE_HIVE_VOTES = "SELECT hive.app_restore_indexes('hivemind_app', 'hivemind_app.hive_votes')"
_ORDERING = [_COMMAND, _CLUSTER, _VACUUM]


class _ProcessExit(BaseException):
    """The process ending mid-statement: no code of the rewrite catches it."""


class _Database:
    """A connection recording its statements, whose registration row carries the clustering mark it keeps.

    CLUSTER sets the mark only once it has completed.
    """

    def __init__(self, registered: bool = True, clustered: bool = False) -> None:
        self.statements: list[str] = []
        self.registered = registered
        self.clustered = clustered
        self.exit_at: str | None = None
        self._lock = threading.Lock()

    def clone(self, name: str) -> _Database:
        return self

    def close(self) -> None:
        pass

    def query_no_return(self, sql: str, **kwargs: Any) -> None:
        with self._lock:
            self.statements.append(sql)
        if sql == self.exit_at:
            raise _ProcessExit
        if sql == _CLUSTER:
            self.clustered = True

    query_no_return_autocommit = query_no_return

    def query_col(self, sql: str, **kwargs: Any) -> list[Any]:
        return []

    def query_row(self, sql: str) -> Any:
        if 'hafd.indexes_constraints' in sql:
            self.query_no_return('registration lookup')
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
        patch.multiple(
            DbState,
            _initial_sync=initial_sync,
            _indexes_were_enabled=False,
            _indexes_were_disabled=True,
            _deferred_index_tables=[],
        ),
        patch('hive.db.schema.ensure_tables_logged', lambda *a: None),
    ):
        yield


def _ordering_statements(statements: list[str]) -> list[str]:
    return [sql for sql in statements if sql in _ORDERING]


def test_initial_sync_clusters_hive_votes_before_restoring_its_indexes() -> None:
    database = _Database()
    with _db_state(database):
        DbState.ensure_indexes_are_enabled()

    statements = database.statements
    assert _ordering_statements(statements) == _ORDERING
    assert statements.index(_VACUUM) < statements.index(_RESTORE_HIVE_VOTES)
    assert database.clustered


def test_rerun_after_the_rewrite_does_not_cluster_again() -> None:
    database = _Database(clustered=True)
    with _db_state(database):
        DbState.ensure_indexes_are_enabled()

    assert 'registration lookup' in database.statements
    assert _ordering_statements(database.statements) == []
    assert _RESTORE_HIVE_VOTES in database.statements


def test_unregistered_index_leaves_hive_votes_unordered_but_restored() -> None:
    database = _Database(registered=False)
    with _db_state(database):
        DbState.ensure_indexes_are_enabled()

    assert _ordering_statements(database.statements) == []
    assert _RESTORE_HIVE_VOTES in database.statements


def test_restore_outside_an_initial_sync_keeps_the_table() -> None:
    database = _Database()
    with _db_state(database, initial_sync=False):
        DbState.ensure_indexes_are_enabled(build_search_index=True)

    assert 'registration lookup' not in database.statements
    assert _ordering_statements(database.statements) == []
    assert _RESTORE_HIVE_VOTES in database.statements


@pytest.mark.parametrize('exit_at', [_COMMAND, _CLUSTER])
def test_ordering_interrupted_before_cluster_completes_is_redone_on_restart(exit_at: str) -> None:
    uninterrupted = _Database()
    with _db_state(uninterrupted):
        DbState.ensure_indexes_are_enabled()

    database = _Database()
    database.exit_at = exit_at
    with _db_state(database), pytest.raises(_ProcessExit):
        DbState.ensure_indexes_are_enabled()
    assert not database.clustered

    database.exit_at = None
    database.statements = []
    with _db_state(database):
        DbState.ensure_indexes_are_enabled()

    assert database.statements == uninterrupted.statements
    assert database.clustered


@pytest.mark.parametrize('exit_at', [_VACUUM, _RESTORE_HIVE_VOTES])
def test_ordering_interrupted_after_cluster_completes_is_not_redone_on_restart(exit_at: str) -> None:
    database = _Database()
    database.exit_at = exit_at
    with _db_state(database), pytest.raises(_ProcessExit):
        DbState.ensure_indexes_are_enabled()
    assert database.clustered

    database.exit_at = None
    database.statements = []
    with _db_state(database):
        DbState.ensure_indexes_are_enabled()

    assert _ordering_statements(database.statements) == []
    assert _RESTORE_HIVE_VOTES in database.statements


def _run_in_threads(
    info: str, methods: Sequence[tuple[str, Callable[..., None], list[Any]]], max_workers: int | None = None
) -> None:
    threads = [threading.Thread(target=method, args=args) for _description, method, args in methods]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()


def test_bm25_build_runs_beside_the_ordering_without_holding_back_its_vacuum() -> None:
    database = _Database()
    votes_restored = threading.Event()

    def build_bm25(db: Any) -> None:
        assert votes_restored.wait(timeout=10), 'the hive_votes restore waited for the BM25 build'
        database.query_no_return('bm25 built')

    def restore(db: Any, full_table_name: str) -> None:
        database.query_no_return(f"SELECT hive.app_restore_indexes('hivemind_app', '{full_table_name}')")
        if full_table_name == 'hivemind_app.hive_votes':
            votes_restored.set()

    with (
        _db_state(database, run_tasks=_run_in_threads),
        patch.object(DbState, '_restore_bm25_index', staticmethod(build_bm25)),
        patch.object(DbState, '_restore_indexes_per_table', staticmethod(restore)),
    ):
        DbState.ensure_indexes_are_enabled(defer_to_finalization=True, build_search_index=True)

    statements = database.statements
    assert _ordering_statements(statements) == _ORDERING
    assert statements.index(_VACUUM) < statements.index('bm25 built')


def test_bm25_build_waits_for_finalization_when_massive_batches_follow_the_restore() -> None:
    database = _Database()
    build = MagicMock()
    with _db_state(database), patch.object(DbState, '_restore_bm25_index', build):
        DbState.ensure_indexes_are_enabled(defer_to_finalization=True)

    build.assert_not_called()
    assert _VACUUM in database.statements
