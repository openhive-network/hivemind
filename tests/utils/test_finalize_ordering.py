"""Guard the #337 finalization ordering contract.

The completion marker (update_last_completed_block) certifies that all
derived-table fills are done, so it must be the very last write of
finalization — never a parallel Part 0 task — and a shutdown request must
stop finalization before the marker, leaving it unset so the next startup
re-runs finalization with the same range.
"""

from unittest.mock import MagicMock, patch

from hive.db.db_state import DbState

BASE = {
    'db': MagicMock(return_value=MagicMock()),
    '_finish_posts_rshares': None,
    'vacuum_tables_in_threads': None,
    '_finish_reputation_notification_scores': None,
}


def _run(massive_sync_preconditions, allowed_continue_checks=None):
    """Run _finish_all_tables with recorded task order and an optional interrupt point.

    allowed_continue_checks: number of can_continue_thread() calls that return
    True before the simulated shutdown request; None means never interrupted.
    """
    calls = []

    def fake_tasks(info, methods):
        calls.append(('parallel', sorted(name for name, _, _ in methods)))

    def fake_marker(db, preconds, first, last):
        calls.append(('marker', preconds, first, last))

    counter = iter(range(1000))

    def can_continue():
        return allowed_continue_checks is None or next(counter) < allowed_continue_checks

    DbState._rshares_recalculated = False
    patches = {
        k: (v if v is not None else staticmethod(lambda *a, _name=k, **kw: calls.append((_name,))))
        for k, v in BASE.items()
    }
    with (
        patch.multiple(DbState, **patches),
        patch.object(DbState, 'process_tasks_in_threads', staticmethod(fake_tasks)),
        patch.object(DbState, '_finalize_completion_marker', staticmethod(fake_marker)),
        patch('hive.signals.can_continue_thread', can_continue),
    ):
        completed = DbState._finish_all_tables(massive_sync_preconditions, 100, 200)
    return completed, calls


def test_marker_is_last_write_initial_path():
    completed, calls = _run(massive_sync_preconditions=True)
    assert completed is True
    assert calls[-1] == ('marker', True, 100, 200)
    parallel_batches = [c for c in calls if c[0] == 'parallel']
    assert len(parallel_batches) == 2  # Part 0 and Part 1
    for _, names in parallel_batches:
        assert 'blocks_consistency_flag' not in names, "marker must not run as a parallel task"


def test_marker_is_last_write_non_initial_path():
    completed, calls = _run(massive_sync_preconditions=False)
    assert completed is True
    assert [c[0] for c in calls] == ['parallel', 'marker']
    assert calls[-1] == ('marker', False, 100, 200)


def test_interrupt_before_fills_skips_everything():
    completed, calls = _run(massive_sync_preconditions=True, allowed_continue_checks=0)
    assert completed is False
    assert not calls


def test_interrupt_before_marker_leaves_marker_unset():
    completed, calls = _run(massive_sync_preconditions=True, allowed_continue_checks=3)
    assert completed is False
    assert any(c[0] == 'parallel' for c in calls), "fills should have run before the interrupt"
    assert not any(c[0] == 'marker' for c in calls), "marker must not be set on an interrupted finalization"
