"""A toast-chunk error in finalization's BM25 index build (#450).

The build reads every row version hive_post_data's heap still holds, so it can
detoast a dead version whose toast is already gone. One such error is absorbed
by a vacuum of hive_post_data and a second build; a second error still fails
finalization before its completion marker.
"""

from typing import Any
from unittest.mock import MagicMock, patch

import psycopg2.errors
import pytest

from hive.db.db_state import DbState

Call = tuple[Any, ...]

TOAST_ERROR = "missing chunk number 0 for toast value 126192046 in pg_toast_40738"


class _FakeBuildDb:
    """A connection whose CREATE INDEX raises DataCorrupted for the first `failures` calls."""

    def __init__(self, calls: list[Call], failures: int) -> None:
        self._calls = calls
        self._failures = failures

    def query_no_return(self, sql: str, **kwargs: Any) -> None:
        assert sql.startswith('CREATE INDEX IF NOT EXISTS hive_post_data_bm25_idx'), sql
        self._calls.append(('create_bm25',))
        if self._failures > 0:
            self._failures -= 1
            raise psycopg2.errors.DataCorrupted(TOAST_ERROR)


def _run(massive_sync_preconditions: bool, failures: int) -> tuple[Any, list[Call]]:
    """Run _finish_all_tables with the real Part 0 pool and BM25 task; every other task only records itself."""
    calls: list[Call] = []
    build_db = _FakeBuildDb(calls, failures)

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
            '_finish_hive_posts',
            '_finish_payout_stats_view',
            '_finish_communities_posts_and_rank',
            '_finish_vote_notifications_ranged',
            '_finish_notification_cache',
            '_finish_vote_notifications',
            '_finish_reputation_notification_scores',
        )
    }
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
        except psycopg2.errors.DataCorrupted as exc:
            result = exc
    return result, calls


@pytest.mark.parametrize('massive_sync_preconditions', [True, False])
def test_one_toast_error_is_absorbed_and_marker_commits_once(massive_sync_preconditions: bool) -> None:
    completed, calls = _run(massive_sync_preconditions, failures=1)

    assert completed is True
    bm25 = [c for c in calls if c[0] in ('create_bm25', 'vacuum')]
    assert bm25 == [('create_bm25',), ('vacuum', 'VACUUM hivemind_app.hive_post_data'), ('create_bm25',)]
    assert [c for c in calls if c[0] == 'marker'] == [('marker', massive_sync_preconditions, 100, 200)]
    assert calls[-1][0] == 'marker'


def test_second_toast_error_fails_finalization_before_marker() -> None:
    result, calls = _run(massive_sync_preconditions=True, failures=2)

    assert isinstance(result, psycopg2.errors.DataCorrupted)
    assert TOAST_ERROR in str(result)
    assert [c[0] for c in calls].count('create_bm25') == 2
    assert not any(c[0] == 'marker' for c in calls)


@pytest.mark.parametrize('massive_sync_preconditions', [True, False])
def test_build_without_error_runs_once_without_vacuum(massive_sync_preconditions: bool) -> None:
    completed, calls = _run(massive_sync_preconditions, failures=0)

    assert completed is True
    assert [c for c in calls if c[0] in ('create_bm25', 'vacuum')] == [('create_bm25',)]
    expected_part0 = {'_finish_hive_feed_cache', '_finish_hive_posts', 'create_bm25'}
    expected_part0 |= (
        {'_finish_payout_stats_view', '_finish_communities_posts_and_rank'}
        if massive_sync_preconditions
        else {'_finish_vote_notifications_ranged'}
    )
    assert expected_part0 <= {c[0] for c in calls}
    assert [c for c in calls if c[0] == 'marker'] == [('marker', massive_sync_preconditions, 100, 200)]
