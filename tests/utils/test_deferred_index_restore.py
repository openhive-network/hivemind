"""Guard the order of hive_posts' index restore around the initial-sync recompute.

On an initial sync, hive_posts' registered indexes are restored after the
recompute of the posts' vote aggregates and children (prepare_posts_children, then
recalculate_posts_votes_and_children over post id ranges) rewrites the table, and
before the finalization steps that find its rows through them. Every other
restore, and every restore outside an initial sync, happens when the indexes are
enabled. The ranges cover every post id once, and a finalization interrupted
among them redoes the whole recompute on restart.
"""

import re
from collections.abc import Callable, Iterator, Sequence
from contextlib import contextmanager
from typing import Any
from unittest.mock import MagicMock, patch

import pytest

from hive.db.db_state import DbState

_RESTORE_HIVE_POSTS = "SELECT hive.app_restore_indexes('hivemind_app', 'hivemind_app.hive_posts')"
_RESTORE_HIVE_VOTES = "SELECT hive.app_restore_indexes('hivemind_app', 'hivemind_app.hive_votes')"
_PREPARE = "SELECT hivemind_app.prepare_posts_children()"
_RANGE = "SELECT hivemind_app.recalculate_posts_votes_and_children("
_CLEANUP = "TRUNCATE TABLE hivemind_app.__post_children"
_MUTED_PARENTS = "SELECT hivemind_app.propagate_all_muted_parents();"
_MARKER = "completion marker"


@contextmanager
def _db_state(initial_sync: bool, max_post_id: int = 0) -> Iterator[list[str]]:
    """Run DbState against a recording connection whose hive_posts ends at `max_post_id`; yield its SQL, in order."""
    statements: list[str] = []
    db = MagicMock()
    db.query_all.return_value = []
    db.query_col.return_value = []
    db.clone.return_value = db
    db.query_no_return.side_effect = statements.append

    def query_one(sql: str) -> int:
        statements.append(sql)
        return max_post_id if 'MAX(id)' in sql else 0

    db.query_one.side_effect = query_one

    def run_tasks(
        info: str, methods: Sequence[tuple[str, Callable[..., None], list[Any]]], max_workers: int | None = None
    ) -> None:
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
            _finalize_completion_marker=staticmethod(lambda *a: statements.append(_MARKER)),
        ),
        patch('hive.db.schema.ensure_tables_logged', lambda *a: None),
        patch('hive.signals.can_continue_thread', lambda: True),
    ):
        yield statements


def _position(statements: list[str], fragment: str) -> int:
    matches = [i for i, sql in enumerate(statements) if fragment in sql]
    assert len(matches) == 1, (fragment, statements)
    return matches[0]


def _ranges(statements: list[str]) -> list[tuple[int, int]]:
    """The post id ranges the recompute ran, in order."""
    return [
        (int(m.group(1)), int(m.group(2)))
        for sql in statements
        if (m := re.search(r'recalculate_posts_votes_and_children\((\d+), (\d+)\)', sql))
    ]


def _last_range(statements: list[str]) -> int:
    return max(i for i, sql in enumerate(statements) if _RANGE in sql)


def test_initial_sync_restores_hive_posts_indexes_after_the_recompute() -> None:
    with _db_state(initial_sync=True) as statements:
        DbState.ensure_indexes_are_enabled(defer_to_finalization=True)
        enabled = list(statements)
        assert DbState.ensure_finalize_massive_sync(10**8, 1) is True

    assert _RESTORE_HIVE_VOTES in enabled
    assert _RESTORE_HIVE_POSTS not in enabled
    restore = _position(statements, _RESTORE_HIVE_POSTS)
    assert _position(statements, _PREPARE) < min(i for i, sql in enumerate(statements) if _RANGE in sql)
    assert _last_range(statements) < _position(statements, _CLEANUP) < restore
    assert restore < _position(statements, 'update_hive_posts_root_id')
    assert restore < _position(statements, 'propagate_all_muted_parents')


def test_indexes_restored_at_once_outside_an_initial_sync() -> None:
    with _db_state(initial_sync=False) as statements:
        DbState.ensure_indexes_are_enabled(defer_to_finalization=True)
        assert _RESTORE_HIVE_POSTS in statements
        assert _RESTORE_HIVE_VOTES in statements
        DbState.ensure_finalize_massive_sync(10**8, 1)

    assert _position(statements, _RESTORE_HIVE_POSTS) < _position(statements, _PREPARE)


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

    assert _PREPARE not in statements
    assert _RESTORE_HIVE_POSTS in statements


class _ProcessExit(BaseException):
    """The process ending mid-finalization: no finalization code catches it."""


def _finalize(statements: list[str]) -> list[str]:
    DbState.ensure_indexes_are_enabled(defer_to_finalization=True)
    DbState.ensure_finalize_massive_sync(10**8, 1)
    return list(statements)


def test_finalization_exited_after_muted_parents_reruns_and_commits_the_marker_once() -> None:
    with _db_state(initial_sync=True) as statements:
        uninterrupted = _finalize(statements)

    finish_muted_parents = DbState._finish_muted_parents

    def exit_after_muted_parents(db: Any) -> None:
        finish_muted_parents(db)
        raise _ProcessExit

    with _db_state(initial_sync=True) as first:
        with patch.object(DbState, '_finish_muted_parents', staticmethod(exit_after_muted_parents)):
            try:
                _finalize(first)
            except _ProcessExit:
                pass
            else:
                raise AssertionError("finalization did not reach the simulated exit")

    with _db_state(initial_sync=True) as restarted:
        _finalize(restarted)

    assert first[-1] == _MUTED_PARENTS
    assert first == uninterrupted[: len(first)]
    assert _MARKER not in first
    assert restarted == uninterrupted
    assert (first + restarted).count(_MARKER) == 1
    assert restarted[-1] == _MARKER


@pytest.mark.parametrize('max_post_id', [0, 5, 1000, 123_456_789])
def test_recompute_ranges_cover_every_post_id_once(max_post_id: int) -> None:
    with _db_state(initial_sync=True, max_post_id=max_post_id) as statements:
        _finalize(statements)

    ranges = _ranges(statements)
    assert len(ranges) == DbState.finalization_workers * DbState._RECOMPUTE_RANGES_PER_WORKER
    assert ranges[0][0] == 0
    assert ranges[-1][1] == 2**31 - 1
    assert all(first <= last for first, last in ranges)
    assert all(prev[1] + 1 == nxt[0] for prev, nxt in zip(ranges, ranges[1:], strict=False))


def test_finalization_exited_among_the_recompute_ranges_reruns_it_whole_and_commits_the_marker_once() -> None:
    with _db_state(initial_sync=True, max_post_id=1000) as statements:
        uninterrupted = _finalize(statements)

    recalculate_posts_range = DbState._recalculate_posts_range
    ran: list[int] = []

    def exit_after_third_range(db: Any, first_id: int, last_id: int) -> None:
        recalculate_posts_range(db, first_id, last_id)
        ran.append(first_id)
        if len(ran) == 3:
            raise _ProcessExit

    with _db_state(initial_sync=True, max_post_id=1000) as first:
        with patch.object(DbState, '_recalculate_posts_range', staticmethod(exit_after_third_range)):
            with pytest.raises(_ProcessExit):
                _finalize(first)

    with _db_state(initial_sync=True, max_post_id=1000) as restarted:
        _finalize(restarted)

    assert len(_ranges(first)) == 3
    assert first == uninterrupted[: len(first)]
    assert _CLEANUP not in first
    assert _MARKER not in first
    assert restarted == uninterrupted
    assert (first + restarted).count(_MARKER) == 1
