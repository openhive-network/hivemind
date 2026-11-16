"""Guard the rewrite of hive_votes in post order at an initial sync's index restore.

The registered (post_id, voter_id) index is built from its registered command,
hive_votes is clustered on it and vacuumed, and only then are its other indexes
restored. A rerun that finds the index already clustered, and every restore
outside an initial sync, leaves the table as it is.
"""

from collections.abc import Callable, Iterator, Sequence
from contextlib import contextmanager
from typing import Any
from unittest.mock import MagicMock, patch

from hive.db.db_state import DbState

_COMMAND = 'create index if not exists hive_votes_post_id_voter_id_idx on hivemind_app.hive_votes (post_id, voter_id)'
_CLUSTER = 'CLUSTER hivemind_app.hive_votes USING hive_votes_post_id_voter_id_idx'
_VACUUM = 'VACUUM (FREEZE, ANALYZE) hivemind_app.hive_votes'
_RESTORE_HIVE_VOTES = "SELECT hive.app_restore_indexes('hivemind_app', 'hivemind_app.hive_votes')"


@contextmanager
def _db_state(initial_sync: bool, registration: dict[str, Any] | None) -> Iterator[list[str]]:
    """Restore indexes against a recording connection whose hafd.indexes_constraints row is `registration`."""
    statements: list[str] = []
    db = MagicMock()
    db.clone.return_value = db
    db.query_col.return_value = []
    db.query_no_return.side_effect = statements.append
    db.query_no_return_autocommit.side_effect = statements.append

    def query_row(sql: str) -> Any:
        if 'hafd.indexes_constraints' in sql:
            statements.append('registration lookup')
            return None if registration is None else MagicMock(_mapping=registration)
        assert 'relallvisible' in sql, sql
        return MagicMock(_mapping={'relpages': 100, 'relallvisible': 100})

    db.query_row.side_effect = query_row

    def run_tasks(
        info: str, methods: Sequence[tuple[str, Callable[..., None], list[Any]]], max_workers: int | None = None
    ) -> None:
        for _description, method, args in methods:
            method(*args)

    with (
        patch.object(DbState, 'db', staticmethod(lambda: db)),
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
        DbState.ensure_indexes_are_enabled()
        yield statements


def test_initial_sync_clusters_hive_votes_before_restoring_its_indexes() -> None:
    with _db_state(True, {'command': _COMMAND, 'clustered': False}) as statements:
        pass

    order = [statements.index(sql) for sql in (_COMMAND, _CLUSTER, _VACUUM, _RESTORE_HIVE_VOTES)]
    assert order == sorted(order)
    assert statements.count(_CLUSTER) == 1


def test_rerun_after_the_rewrite_does_not_cluster_again() -> None:
    with _db_state(True, {'command': _COMMAND, 'clustered': True}) as statements:
        pass

    assert 'registration lookup' in statements
    assert _COMMAND not in statements
    assert _CLUSTER not in statements
    assert _VACUUM not in statements
    assert _RESTORE_HIVE_VOTES in statements


def test_unregistered_index_leaves_hive_votes_unordered_but_restored() -> None:
    with _db_state(True, None) as statements:
        pass

    assert _CLUSTER not in statements
    assert _RESTORE_HIVE_VOTES in statements


def test_restore_outside_an_initial_sync_keeps_the_table() -> None:
    with _db_state(False, {'command': _COMMAND, 'clustered': False}) as statements:
        pass

    assert 'registration lookup' not in statements
    assert _CLUSTER not in statements
    assert _RESTORE_HIVE_VOTES in statements
