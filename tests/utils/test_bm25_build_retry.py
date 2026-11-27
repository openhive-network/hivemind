"""A toast-chunk error in finalization's BM25 index build (#450, #492).

The build reads every row version hive_post_data's heap still holds, so it can
detoast a dead version whose toast is already gone. Toast autovacuum, which
removed those chunks once a co-tenant's transaction stopped holding the horizon
back, is off for every build attempt and back on after the last. One such error
is still absorbed by a vacuum of hive_post_data and a second build; a second
error still fails finalization before its completion marker.

The build starts once the hive_posts recompute has committed, so its snapshot
does not keep the row versions the recompute replaced (#485).
"""

import time
from collections.abc import Callable
from concurrent.futures import Future
from typing import Any
from unittest.mock import MagicMock, patch

import psycopg2.errors
import pytest

from hive.db.db_state import DbState

Call = tuple[Any, ...]

TOAST_ERROR = "missing chunk number 0 for toast value 126192046 in pg_toast_40738"
TOAST_AUTOVACUUM_OFF = ('alter', 'ALTER TABLE hivemind_app.hive_post_data SET (toast.autovacuum_enabled = off)')
TOAST_AUTOVACUUM_RESET = ('alter', 'ALTER TABLE hivemind_app.hive_post_data RESET (toast.autovacuum_enabled)')


class _FakeBuildDb:
    """A connection whose CREATE INDEX raises DataCorrupted for the first `failures` calls."""

    def __init__(self, calls: list[Call], failures: int, index_exists: bool = False) -> None:
        self._calls = calls
        self._failures = failures
        self._index_exists = index_exists

    def query_one(self, sql: str, **kwargs: Any) -> bool:
        assert "to_regclass('hivemind_app.hive_post_data_bm25_idx')" in sql, sql
        return self._index_exists

    def query_no_return(self, sql: str, **kwargs: Any) -> None:
        if sql.startswith('ALTER TABLE'):
            self._calls.append(('alter', sql))
            return
        assert sql.startswith('CREATE INDEX IF NOT EXISTS hive_post_data_bm25_idx'), sql
        self._calls.append(('create_bm25',))
        if self._failures > 0:
            self._failures -= 1
            raise psycopg2.errors.DataCorrupted(TOAST_ERROR)


def _recompute(calls: list[Call], delay: float = 0.0) -> Callable[..., None]:
    """A hive_posts task that commits its recompute after `delay` seconds."""

    def finish_hive_posts(*args: Any) -> None:
        recomputed: Future[None] = args[-1]
        time.sleep(delay)
        calls.append(('_finish_hive_posts',))
        recomputed.set_result(None)

    return finish_hive_posts


def _run(
    massive_sync_preconditions: bool,
    failures: int,
    recompute_delay: float = 0.0,
    hive_posts: Callable[..., None] | None = None,
    index_exists: bool = False,
) -> tuple[Any, list[Call]]:
    """Run _finish_all_tables with the real Part 0 pool and BM25 task; every other task only records itself."""
    calls: list[Call] = []
    build_db = _FakeBuildDb(calls, failures, index_exists)

    def disposer(db: Any, name: str) -> MagicMock:
        mgr = MagicMock()
        mgr.__enter__.return_value.db = build_db
        return mgr

    def recorder(name: str) -> staticmethod[..., None]:
        return staticmethod(lambda *a, **kw: calls.append((name,)))

    def fake_vacuum(db: Any, name: str, sql: str) -> None:
        calls.append(('vacuum', sql))

    def fake_marker(db: Any, preconds: bool, first: int, last: int) -> None:
        calls.append(('marker', preconds, first, last))

    stubs: dict[str, Any] = {
        name: recorder(name)
        for name in (
            '_finish_hive_feed_cache',
            '_finish_payout_stats_view',
            '_finish_communities_posts_and_rank',
            '_finish_vote_notifications_ranged',
            '_finish_notification_cache',
            '_finish_vote_notifications',
            '_finish_reputation_notification_scores',
        )
    }
    stubs['_wait_for_reputation_tracker'] = staticmethod(lambda *a: True)
    stubs['_finish_hive_posts'] = staticmethod(hive_posts or _recompute(calls, recompute_delay))
    with (
        patch.multiple(DbState, db=MagicMock(return_value=MagicMock()), **stubs),
        patch.object(DbState, '_run_vacuum', staticmethod(fake_vacuum)),
        patch.object(DbState, '_finalize_completion_marker', staticmethod(fake_marker)),
        patch('hive.db.db_state.AutoDbDisposer', disposer),
        patch('hive.db.schema.pg_search_available', True),
        patch('hive.signals.can_continue_thread', lambda: True),
    ):
        try:
            result = DbState._finish_all_tables(massive_sync_preconditions, 100, 200)
        except (psycopg2.errors.DataCorrupted, psycopg2.errors.QueryCanceled) as exc:
            result = exc
    return result, calls


@pytest.mark.parametrize('massive_sync_preconditions', [True, False])
def test_one_toast_error_is_absorbed_and_marker_commits_once(massive_sync_preconditions: bool) -> None:
    completed, calls = _run(massive_sync_preconditions, failures=1)

    assert completed is True
    bm25 = [c for c in calls if c[0] in ('alter', 'create_bm25', 'vacuum')]
    assert bm25 == [
        TOAST_AUTOVACUUM_OFF,
        ('create_bm25',),
        ('vacuum', 'VACUUM hivemind_app.hive_post_data'),
        ('create_bm25',),
        TOAST_AUTOVACUUM_RESET,
    ]
    assert [c for c in calls if c[0] == 'marker'] == [('marker', massive_sync_preconditions, 100, 200)]
    assert calls[-1][0] == 'marker'


def test_second_toast_error_fails_finalization_before_marker() -> None:
    result, calls = _run(massive_sync_preconditions=True, failures=2)

    assert isinstance(result, psycopg2.errors.DataCorrupted)
    assert TOAST_ERROR in str(result)
    assert [c[0] for c in calls].count('create_bm25') == 2
    assert [c for c in calls if c[0] == 'alter'] == [TOAST_AUTOVACUUM_OFF, TOAST_AUTOVACUUM_RESET]
    assert calls.index(TOAST_AUTOVACUUM_RESET) > max(i for i, c in enumerate(calls) if c[0] == 'create_bm25')
    assert not any(c[0] == 'marker' for c in calls)


@pytest.mark.parametrize('massive_sync_preconditions', [True, False])
def test_build_without_error_runs_once_without_vacuum(massive_sync_preconditions: bool) -> None:
    completed, calls = _run(massive_sync_preconditions, failures=0)

    assert completed is True
    assert [c for c in calls if c[0] in ('alter', 'create_bm25', 'vacuum')] == [
        TOAST_AUTOVACUUM_OFF,
        ('create_bm25',),
        TOAST_AUTOVACUUM_RESET,
    ]
    expected_part0 = {'_finish_hive_feed_cache', '_finish_hive_posts', 'create_bm25'}
    expected_part0 |= (
        {'_finish_payout_stats_view', '_finish_communities_posts_and_rank'}
        if massive_sync_preconditions
        else {'_finish_vote_notifications_ranged'}
    )
    assert expected_part0 <= {c[0] for c in calls}
    assert [c for c in calls if c[0] == 'marker'] == [('marker', massive_sync_preconditions, 100, 200)]


def test_build_starts_after_the_hive_posts_recompute_commits() -> None:
    completed, calls = _run(massive_sync_preconditions=True, failures=0, recompute_delay=0.3)

    assert completed is True
    names = [c[0] for c in calls]
    assert names.index('_finish_hive_posts') < names.index('create_bm25')


def test_build_skipped_when_the_hive_posts_task_fails_before_its_recompute_commits() -> None:
    def failing_recompute(db: Any, sql: str, **kwargs: Any) -> None:
        raise psycopg2.errors.QueryCanceled("canceling statement due to user request")

    with patch.object(DbState, '_execute_query_with_modified_work_mem', staticmethod(failing_recompute)):
        result, calls = _run(massive_sync_preconditions=True, failures=0, hive_posts=DbState._finish_hive_posts)

    assert isinstance(result, psycopg2.errors.QueryCanceled)
    assert not any(c[0] in ('alter', 'create_bm25', 'marker') for c in calls)


def test_index_built_by_the_index_restore_is_not_built_again() -> None:
    completed, calls = _run(massive_sync_preconditions=True, failures=0, index_exists=True)

    assert completed is True
    assert not any(c[0] in ('alter', 'create_bm25', 'vacuum') for c in calls)
    assert [c for c in calls if c[0] == 'marker'] == [('marker', True, 100, 200)]
