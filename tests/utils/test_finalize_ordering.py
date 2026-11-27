"""Guard the #337 finalization ordering contract.

The completion marker (update_last_completed_block) certifies that all
derived-table fills are done, so it must be the very last write of
finalization — never a parallel Part 0 task — and a shutdown request must
stop finalization before the marker, leaving it unset so the next startup
re-runs finalization with the same range.
"""

from typing import Any
from unittest.mock import MagicMock, patch

from hive.db.db_state import DbState

BASE = {
    'db': MagicMock(return_value=MagicMock()),
    'vacuum_tables_in_threads': None,
    '_finish_reputation_notification_scores': None,
}


def _run(
    massive_sync_preconditions: bool, allowed_continue_checks: int | None = None, last_completed: int = 100
) -> tuple[bool, list[tuple[Any, ...]]]:
    """Run _finish_all_tables with recorded task order and an optional interrupt point.

    allowed_continue_checks: number of can_continue_thread() calls that return
    True before the simulated shutdown request; None means never interrupted.
    """
    calls: list[tuple[Any, ...]] = []

    def fake_tasks(info: str, methods: list[tuple[str, Any, Any]], max_workers: int | None = None) -> None:
        calls.append(('parallel', sorted(name for name, _, _ in methods)))

    def fake_marker(db: Any, preconds: bool, first: int, last: int) -> None:
        calls.append(('marker', preconds, first, last))

    counter = iter(range(1000))

    def can_continue() -> bool:
        return allowed_continue_checks is None or next(counter) < allowed_continue_checks

    def fake_wait(db: Any, block_num: int) -> bool:
        calls.append(('_wait_for_reputation_tracker', block_num))
        return True

    patches: dict[str, Any] = {
        k: (v if v is not None else staticmethod(lambda *a, _name=k, **kw: calls.append((_name,))))
        for k, v in BASE.items()
    }
    patches['_wait_for_reputation_tracker'] = staticmethod(fake_wait)
    with (
        patch.multiple(DbState, **patches),
        patch.object(DbState, 'process_tasks_in_threads', staticmethod(fake_tasks)),
        patch.object(DbState, '_finalize_completion_marker', staticmethod(fake_marker)),
        patch('hive.signals.can_continue_thread', can_continue),
    ):
        completed = DbState._finish_all_tables(massive_sync_preconditions, last_completed, 200)
    return completed, calls


def test_marker_is_last_write_initial_path():
    completed, calls = _run(massive_sync_preconditions=True)
    assert completed is True
    assert calls[-1] == ('marker', True, 100, 200)
    parallel_batches = [c for c in calls if c[0] == 'parallel']
    assert len(parallel_batches) == 2  # Part 0 and Part 1
    for _, names in parallel_batches:
        assert 'blocks_consistency_flag' not in names, "marker must not run as a parallel task"


def test_hive_posts_writers_share_one_task():
    """Concurrent UPDATEs of hive_posts would wait on each other's row locks; one Part 0 task owns them all."""
    _, calls = _run(massive_sync_preconditions=True)
    part0 = next(c[1] for c in calls if c[0] == 'parallel')
    assert 'hive_posts' in part0
    assert 'muted_parents' not in part0
    assert ('vacuum_tables_in_threads',) not in calls, "no vacuum between hive_posts passes"


def test_marker_is_last_write_non_initial_path():
    completed, calls = _run(massive_sync_preconditions=False)
    assert completed is True
    assert [c[0] for c in calls] == ['parallel', 'marker']
    assert calls[-1] == ('marker', False, 100, 200)


def test_short_initial_sync_rescores_reputation_notifications_before_marker() -> None:
    """An initial sync's flushes defer the score > 0 cut to the rescore, whatever its length."""
    completed, calls = _run(massive_sync_preconditions=False, last_completed=1)
    assert completed is True
    assert [c[0] for c in calls] == [
        'parallel',
        '_wait_for_reputation_tracker',
        '_finish_reputation_notification_scores',
        'marker',
    ]
    assert calls[1] == ('_wait_for_reputation_tracker', 200), "the rescoring waits for reptracker at hivemind's block"


def test_interrupt_before_fills_skips_everything():
    completed, calls = _run(massive_sync_preconditions=True, allowed_continue_checks=0)
    assert completed is False
    assert not calls


def test_interrupt_before_marker_leaves_marker_unset():
    completed, calls = _run(massive_sync_preconditions=True, allowed_continue_checks=2)
    assert completed is False
    assert any(c[0] == 'parallel' for c in calls), "fills should have run before the interrupt"
    assert not any(c[0] == 'marker' for c in calls), "marker must not be set on an interrupted finalization"
