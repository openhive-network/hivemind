"""Finalization does not hold go-live for reputation_tracker: a rescore it is not ready for goes to live sync.

reputation_notification scores are rescored from reptracker's reputations at hivemind's
block (#531). reptracker, one serial backend, may reach that block long after hivemind
finished every other finalization step; finalization then leaves the rescore pending
and commits its completion marker, and live sync runs the rescore in the transaction of
the first range it processes once reptracker has the blocks hivemind completed.
"""

from typing import Any
from unittest.mock import MagicMock, patch

from hive.db.db_state import DbState


class _FakeHaf:
    """reptracker's context block, whether its block processor runs, and the pending rescore marker."""

    def __init__(self, reptracker_block: int, processor_running: bool = True, pending_block: int | None = None) -> None:
        self.reptracker_block = reptracker_block
        self.processor_running = processor_running
        self.pending_block = pending_block
        self.statements: list[str] = []
        self.db = MagicMock()
        self.db.clone.return_value = self.db
        self.db.query_one.side_effect = self._query_one
        self.db.query_all.side_effect = self._query_all
        self.db.query_no_return.side_effect = self._execute
        self.db.query.side_effect = self._execute

    def _query_one(self, sql: str, **kwargs: Any) -> Any:
        if 'app_get_current_block_num' in sql:
            assert "'reptracker_app'" in sql
            return self.reptracker_block
        if 'pg_locks' in sql:
            assert kwargs == {'app_name': 'hivemind'}
            return self.processor_running
        if '_reputation_rescore_pending' in sql:
            return self.pending_block is not None
        raise AssertionError(f"unexpected query: {sql}")

    def _query_all(self, sql: str, **kwargs: Any) -> Any:
        assert '_reputation_rescore_pending' in sql and "'reptracker_app'" in sql, sql
        return [] if self.pending_block is None else [(self.pending_block, self.reptracker_block)]

    def _execute(self, sql: str, **kwargs: Any) -> None:
        sql = ' '.join(sql.split())
        self.statements.append(sql)
        if sql.startswith('DELETE FROM hivemind_app._reputation_rescore_pending'):
            self.pending_block = None
        elif sql.startswith('INSERT INTO hivemind_app._reputation_rescore_pending'):
            self.pending_block = int(sql.rsplit('(', 1)[1].rstrip(')'))

    def rescored(self) -> bool:
        return any(s.startswith('WITH log_account_rep') for s in self.statements)


def _finish(haf: _FakeHaf, massive_sync_preconditions: bool = True) -> tuple[bool, list[Any]]:
    """Run a finalization ending at block 200, recording the rescore and the marker with the pending marker."""
    calls: list[Any] = []

    def rescore(db: Any) -> None:
        calls.append(('rescore', haf.reptracker_block))
        haf.pending_block = None

    def marker(*args: Any) -> None:
        calls.append(('marker', haf.pending_block))

    with (
        patch.object(DbState, 'db', staticmethod(lambda: haf.db)),
        patch.object(DbState, 'process_tasks_in_threads', staticmethod(lambda *a, **kw: None)),
        patch.object(DbState, '_finish_reputation_notification_scores', staticmethod(rescore)),
        patch.object(DbState, '_finalize_completion_marker', staticmethod(marker)),
        patch('hive.signals.can_continue_thread', lambda: True),
    ):
        completed = DbState._finish_all_tables(massive_sync_preconditions, 100, 200)
    return completed, calls


def _live(haf: _FakeHaf, completed_block: int) -> None:
    DbState.rescore_pending_reputation_notifications(haf.db, completed_block)


def test_finalization_rescores_when_reptracker_has_hiveminds_block() -> None:
    haf = _FakeHaf(250)
    completed, calls = _finish(haf)
    assert completed is True
    assert calls == [('rescore', 250), ('marker', None)]
    assert not any('pg_locks' in c.args[0] for c in haf.db.query_one.call_args_list)


def test_finalization_rescores_when_no_reptracker_processor_runs() -> None:
    """Nothing would advance reptracker (a setup syncing it after hivemind): rescore from what it has."""
    haf = _FakeHaf(150, processor_running=False)
    completed, calls = _finish(haf)
    assert completed is True
    assert calls == [('rescore', 150), ('marker', None)]


def test_finalization_behind_reptracker_commits_the_marker_with_the_rescore_pending() -> None:
    haf = _FakeHaf(120)
    with patch('hive.db.db_state.sleep', side_effect=AssertionError('finalization waited for reptracker')):
        completed, calls = _finish(haf)
    assert completed is True
    assert calls == [('marker', 200)], "the pending rescore is durable before the completion marker"
    assert not haf.rescored()


def test_a_catch_up_finalization_owes_a_pending_rescore() -> None:
    haf = _FakeHaf(300, pending_block=200)
    completed, calls = _finish(haf, massive_sync_preconditions=False)
    assert completed is True
    assert calls == [('rescore', 300), ('marker', None)]


def test_a_catch_up_finalization_without_a_pending_rescore_does_not_rescore() -> None:
    haf = _FakeHaf(120)
    completed, calls = _finish(haf, massive_sync_preconditions=False)
    assert completed is True
    assert calls == [('marker', None)]


def test_live_sync_without_a_pending_rescore_reads_only_the_marker() -> None:
    haf = _FakeHaf(120)
    _live(haf, 500)
    assert haf.statements == []
    assert haf.db.query_all.call_count == 1


def test_live_sync_keeps_the_rescore_pending_while_reptracker_is_behind() -> None:
    haf = _FakeHaf(499, pending_block=200)
    _live(haf, 500)
    assert haf.statements == []
    assert haf.pending_block == 200


def test_live_sync_rescores_in_its_own_transaction_once_reptracker_has_its_blocks() -> None:
    """The rescore, the deletion of the rows scoring <= 0 and of the marker, and no transaction of its own."""
    haf = _FakeHaf(500, pending_block=200)
    _live(haf, 500)
    assert [' '.join(s.split()[:3]) for s in haf.statements] == [
        'WITH log_account_rep AS',
        'DELETE FROM hivemind_app.hive_notification_cache',
        'DELETE FROM hivemind_app._reputation_rescore_pending',
    ]
    assert 'score <= 0' in haf.statements[1]
    assert haf.pending_block is None
    assert haf.db.clone.call_count == 0

    haf.statements.clear()
    _live(haf, 501)
    assert haf.statements == [], "a rescore runs once"


def test_the_finalization_left_rescore_runs_in_live_sync_after_reptracker_catches_up() -> None:
    haf = _FakeHaf(120)
    completed, calls = _finish(haf)
    assert completed is True and calls == [('marker', 200)]

    for block in range(200, 210):
        _live(haf, block)
    assert not haf.rescored()

    haf.reptracker_block = 210
    _live(haf, 210)
    assert haf.rescored()
    assert haf.pending_block is None
