"""Finalization rescores reputation notifications from reptracker's reputations at hivemind's block (#531).

reputation_tracker syncs beside hivemind, and faster massive sync reaches finalization
before reptracker reaches its block. A rescoring then read reputations still behind,
so the massive-synced notifications scored lower than the same ones synced live.
"""

from collections.abc import Callable
from typing import Any
from unittest.mock import MagicMock, patch

from hive.db.db_state import DbState


class _FakeHaf:
    """reptracker's context block, advancing on each poll, and whether its block processor runs."""

    def __init__(self, reptracker_blocks: list[int], processor_running: bool = True) -> None:
        self._blocks = iter(reptracker_blocks)
        self.block = 0
        self.processor_running = processor_running
        self.db = MagicMock()
        self.db.query_one.side_effect = self._query_one

    def _query_one(self, sql: str, **kwargs: Any) -> Any:
        if 'app_get_current_block_num' in sql:
            assert "'reptracker_app'" in sql
            self.block = next(self._blocks, self.block)
            return self.block
        if 'pg_locks' in sql:
            assert kwargs == {'app_name': 'hivemind'}
            return self.processor_running
        raise AssertionError(f"unexpected query: {sql}")


def _finish(haf: _FakeHaf, can_continue: Callable[[], bool] = lambda: True) -> tuple[bool, list[Any]]:
    """Run an initial-path finalization ending at block 200, recording reptracker's block when it rescores."""
    calls: list[Any] = []

    def rescore(db: Any) -> None:
        calls.append(('rescore', haf.block))

    def marker(*args: Any) -> None:
        calls.append(('marker',))

    with (
        patch.object(DbState, 'db', staticmethod(lambda: haf.db)),
        patch.object(DbState, 'process_tasks_in_threads', staticmethod(lambda *a, **kw: None)),
        patch.object(DbState, '_finish_reputation_notification_scores', staticmethod(rescore)),
        patch.object(DbState, '_finalize_completion_marker', staticmethod(marker)),
        patch.object(DbState, '_REPTRACKER_POLL_SECONDS', 0.0),
        patch('hive.signals.can_continue_thread', can_continue),
    ):
        completed = DbState._finish_all_tables(True, 100, 200)
    return completed, calls


def test_rescoring_waits_for_reptracker_to_reach_hivemind_block() -> None:
    haf = _FakeHaf([120, 160, 199, 200])
    completed, calls = _finish(haf)
    assert completed is True
    assert calls == [('rescore', 200), ('marker',)]


def test_rescoring_runs_at_once_when_reptracker_is_ahead() -> None:
    haf = _FakeHaf([250])
    completed, calls = _finish(haf)
    assert completed is True
    assert calls == [('rescore', 250), ('marker',)]
    assert not any('pg_locks' in c.args[0] for c in haf.db.query_one.call_args_list)


def test_rescoring_proceeds_when_no_reptracker_processor_runs() -> None:
    """Nothing would advance reptracker (a setup syncing it after hivemind): rescore from what it has."""
    haf = _FakeHaf([150], processor_running=False)
    completed, calls = _finish(haf)
    assert completed is True
    assert calls == [('rescore', 150), ('marker',)]


def test_shutdown_while_waiting_leaves_rescoring_and_marker_undone() -> None:
    haf = _FakeHaf([120] * 10)
    checks = iter(range(100))
    # The checks before Part 0 and Part 1 and the wait's first pass; the shutdown comes on its second.
    completed, calls = _finish(haf, can_continue=lambda: next(checks) < 3)
    assert completed is False
    assert calls == []
