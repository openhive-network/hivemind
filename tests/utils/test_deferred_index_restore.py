"""Guard the order of hive_posts' index restore around the initial-sync recompute.

On an initial sync, hive_posts' registered indexes are restored after
recalculate_all_posts_votes_and_children rewrites the table, and before the
finalization steps that find its rows through them. Every other restore, and
every restore outside an initial sync, happens when the indexes are enabled.
"""

from collections.abc import Callable, Iterator, Sequence
from contextlib import contextmanager
from typing import Any
from unittest.mock import MagicMock, patch

from hive.db.db_state import DbState

_RESTORE_HIVE_POSTS = "SELECT hive.app_restore_indexes('hivemind_app', 'hivemind_app.hive_posts')"
_RESTORE_HIVE_VOTES = "SELECT hive.app_restore_indexes('hivemind_app', 'hivemind_app.hive_votes')"
_RECOMPUTE = "SELECT hivemind_app.recalculate_all_posts_votes_and_children()"


@contextmanager
def _db_state(initial_sync: bool) -> Iterator[list[str]]:
    """Run DbState against a recording connection; yield the SQL it issues, in order."""
    statements: list[str] = []
    db = MagicMock()
    db.query_all.return_value = []
    db.clone.return_value = db
    db.query_no_return.side_effect = statements.append

    def query_one(sql: str) -> int:
        statements.append(sql)
        return 0

    db.query_one.side_effect = query_one

    def run_tasks(info: str, methods: Sequence[tuple[str, Callable[..., None], list[Any]]]) -> None:
        for description, method, args in methods:
            if description.startswith('VACUUM ') or description in (
                'hive_feed_cache',
                'payout_stats_view',
                'communities_posts_and_rank',
                'bm25_index',
                'notification_cache',
                'vote_notifications',
            ):
                continue
            method(*args)

    with (
        patch.object(DbState, 'db', staticmethod(lambda: db)),
        patch.object(DbState, 'process_tasks_in_threads', staticmethod(run_tasks)),
        patch.object(
            DbState,
            '_execute_query_with_modified_work_mem',
            staticmethod(lambda db, sql, **kwargs: statements.append(sql.rstrip(';'))),
        ),
        patch.multiple(
            DbState,
            _initial_sync=initial_sync,
            _indexes_were_enabled=False,
            _indexes_were_disabled=True,
            _deferred_index_tables=[],
            _finish_reputation_notification_scores=staticmethod(lambda *a: None),
            _finalize_completion_marker=staticmethod(lambda *a: None),
        ),
        patch('hive.db.schema.set_logged_table_attribute', lambda *a: None),
        patch('hive.signals.can_continue_thread', lambda: True),
    ):
        yield statements


def _position(statements: list[str], fragment: str) -> int:
    matches = [i for i, sql in enumerate(statements) if fragment in sql]
    assert len(matches) == 1, (fragment, statements)
    return matches[0]


def test_initial_sync_restores_hive_posts_indexes_after_the_recompute() -> None:
    with _db_state(initial_sync=True) as statements:
        DbState.ensure_indexes_are_enabled(defer_to_finalization=True)
        enabled = list(statements)
        assert DbState.ensure_finalize_massive_sync(10**8, 1) is True

    assert _RESTORE_HIVE_VOTES in enabled
    assert _RESTORE_HIVE_POSTS not in enabled
    recompute = _position(statements, _RECOMPUTE)
    restore = _position(statements, _RESTORE_HIVE_POSTS)
    assert recompute < restore
    assert restore < _position(statements, 'update_hive_posts_root_id')
    assert restore < _position(statements, 'propagate_all_muted_parents')


def test_indexes_restored_at_once_outside_an_initial_sync() -> None:
    with _db_state(initial_sync=False) as statements:
        DbState.ensure_indexes_are_enabled(defer_to_finalization=True)
        assert _RESTORE_HIVE_POSTS in statements
        assert _RESTORE_HIVE_VOTES in statements
        DbState.ensure_finalize_massive_sync(10**8, 1)

    assert _position(statements, _RESTORE_HIVE_POSTS) < _position(statements, _RECOMPUTE)


def test_enabling_without_deferral_restores_deferred_indexes() -> None:
    with _db_state(initial_sync=True) as statements:
        DbState.ensure_indexes_are_enabled(defer_to_finalization=True)
        assert _RESTORE_HIVE_POSTS not in statements
        DbState.ensure_indexes_are_enabled()
        assert _RESTORE_HIVE_POSTS in statements


def test_interrupted_finalization_still_restores_deferred_indexes() -> None:
    with _db_state(initial_sync=True) as statements:
        DbState.ensure_indexes_are_enabled(defer_to_finalization=True)
        with patch('hive.signals.can_continue_thread', lambda: False):
            assert DbState.ensure_finalize_massive_sync(10**8, 1) is True

    assert _RECOMPUTE not in statements
    assert _RESTORE_HIVE_POSTS in statements
