"""Pipelined massive sync: a batch's Stage B runs on its own thread beside the next batch's Stage A."""

import logging
import threading
from collections.abc import Iterator
from concurrent.futures import ThreadPoolExecutor
from typing import Any
from unittest.mock import MagicMock, patch

import psycopg2
import pytest

from hive.db.db_state import DbState
from hive.indexer.blocks import Blocks
from hive.indexer.community import Community
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.indexer.follow import Follow
from hive.indexer.post_data_cache import PostDataCache
from hive.indexer.posts import Posts
from hive.indexer.reblog import Reblog
from hive.indexer.sync import SyncHiveDb


class _Pipeline:
    """Stands in for the stages' SQL: records the order of Stage A, the handoffs and Stage B."""

    def __init__(self) -> None:
        self.events: list[tuple[str, int] | str] = []
        self.gates: dict[int, threading.Event] = {}
        self.failing: set[int] = set()
        self.cashout: dict[int, int] = {}
        self.stage_b_db = MagicMock(name='stage_b_db')

    def gate(self, first_block: int) -> threading.Event:
        return self.gates.setdefault(first_block, threading.Event())

    def stage_a(
        self, db: Any, first: int, last: int, prefetch: Any, next_range: Any, phase_times: dict[str, float]
    ) -> tuple[list[Any], bool, None]:
        self.events.append(('A', first))
        phase_times['posts'] = 0.0
        return [], False, None

    def stage_b(
        self,
        db: Any,
        first: int,
        last: int,
        post_results: Any,
        applied: bool,
        phase_times: dict[str, float],
        cashout: int,
    ) -> None:
        assert db is self.stage_b_db, 'Stage B runs on its own connection'
        assert self.gate(first).wait(5), f'Stage B of {first} was never released'
        if first in self.failing:
            raise RuntimeError(f'Stage B of {first} failed')
        self.cashout[first] = cashout
        self.events.append(('B', first))

    def hand_off(self, db: Any) -> None:
        self.events.append('handoff')

    def deleted_rows(self) -> list[str]:
        return [c.args[0] for c in self.stage_b_db.query_no_return.call_args_list if 'DELETE' in c.args[0]]


@pytest.fixture
def pipeline(monkeypatch: pytest.MonkeyPatch) -> Iterator[_Pipeline]:
    p = _Pipeline()
    monkeypatch.setattr(Blocks, '_pipelined', True)
    monkeypatch.setattr(Blocks, '_kill_point', None)
    monkeypatch.setattr(Blocks, '_stage_b_future', None)
    monkeypatch.setattr(Blocks, '_stage_b_pool', None)
    monkeypatch.setattr(Blocks, '_stage_b_first_block', None)
    monkeypatch.setattr(Blocks, '_run_stage_a', p.stage_a)
    monkeypatch.setattr(Blocks, '_run_stage_b', p.stage_b)
    monkeypatch.setattr(Blocks, '_hand_off_to_stage_b', p.hand_off)
    monkeypatch.setattr(Blocks, '_log_phase_summary', lambda *args: None)
    monkeypatch.setattr(DbAdapterHolder, '_stage_b_processing_db', p.stage_b_db)
    monkeypatch.setattr(DbAdapterHolder, '_block_processing_thread_sync_db', MagicMock(name='common_db'))
    monkeypatch.setattr('hive.indexer.blocks.set_exception_thrown', MagicMock())
    yield p
    for gate in p.gates.values():
        gate.set()
    Blocks._shut_down_stage_b()


def _in_thread(fn: Any, *args: Any) -> Any:
    pool = ThreadPoolExecutor(max_workers=1)
    future = pool.submit(fn, *args)
    pool.shutdown(wait=False)
    return future


def test_stage_a_of_the_next_batch_runs_beside_stage_b_and_hands_off_only_after_it(
    pipeline: _Pipeline, caplog: pytest.LogCaptureFixture, monkeypatch: pytest.MonkeyPatch
) -> None:
    caplog.set_level(logging.INFO, logger='hive.indexer.blocks')

    monkeypatch.setattr(Blocks, '_last_safe_cashout_block', 100)
    Blocks.process_multi_sql_pipelined(1, 10)
    assert pipeline.events == [('A', 1), 'handoff']

    monkeypatch.setattr(Blocks, '_last_safe_cashout_block', 200)  # set_end_of_sync_lib for the next batch
    second = _in_thread(Blocks.process_multi_sql_pipelined, 11, 20)
    for _ in range(100):
        if ('A', 11) in pipeline.events:
            break
        threading.Event().wait(0.01)
    threading.Event().wait(0.05)
    assert pipeline.events == [('A', 1), 'handoff', ('A', 11)], 'no handoff while Stage B of the batch before runs'
    assert not second.done()

    pipeline.gate(1).set()
    second.result(timeout=5)
    pipeline.gate(11).set()
    Blocks.wait_for_stage_b()

    assert pipeline.events == [('A', 1), 'handoff', ('A', 11), ('B', 1), 'handoff', ('B', 11)]
    assert pipeline.cashout == {1: 100, 11: 200}, 'each Stage B pays out as of its own batch'
    assert pipeline.deleted_rows() == [
        'DELETE FROM hivemind_app._batch_queue WHERE first_block = 1',
        'DELETE FROM hivemind_app._batch_queue WHERE first_block = 11',
    ]
    timing = [r.getMessage() for r in caplog.records if '[STAGE-TIMING]' in r.getMessage()]
    assert sorted(t.split(' start=')[0] for t in timing) == [
        '[STAGE-TIMING] blocks=1-10 stage=A',
        '[STAGE-TIMING] blocks=1-10 stage=B',
        '[STAGE-TIMING] blocks=11-20 stage=A',
        '[STAGE-TIMING] blocks=11-20 stage=B',
    ]
    (second_a,) = (t for t in timing if 'blocks=11-20 stage=A' in t)
    assert float(second_a.split('wait_for_b=')[1].split()[0]) > 0, 'Stage A of 11-20 waited for Stage B of 1-10'


def test_a_failed_stage_b_stops_the_next_batch_before_its_handoff_and_keeps_its_row(pipeline: _Pipeline) -> None:
    pipeline.failing.add(1)
    pipeline.gate(1).set()

    Blocks.process_multi_sql_pipelined(1, 10)
    with pytest.raises(RuntimeError, match='Stage B of 1 failed'):
        Blocks.process_multi_sql_pipelined(11, 20)

    assert pipeline.events == [('A', 1), 'handoff', ('A', 11)]
    assert pipeline.deleted_rows() == []
    Blocks.wait_for_stage_b()  # raised once only


def test_a_failed_stage_b_surfaces_once_it_has_ended_without_waiting_for_a_running_one(pipeline: _Pipeline) -> None:
    pipeline.failing.add(1)
    Blocks.process_multi_sql_pipelined(1, 10)
    Blocks.raise_stage_b_error()  # still running: nothing to raise

    pipeline.gate(1).set()
    for _ in range(500):
        if Blocks._stage_b_future is None or Blocks._stage_b_future.done():
            break
        threading.Event().wait(0.01)
    with pytest.raises(RuntimeError, match='Stage B of 1 failed'):
        Blocks.raise_stage_b_error()


def test_the_stage_a_committed_kill_point_exits_after_the_next_stage_a_with_stage_b_held(
    pipeline: _Pipeline, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(Blocks, '_kill_point', ('stage_a_committed', 1))
    held = threading.Event()
    monkeypatch.setattr(Blocks, '_kill_hold', held)
    exits = MagicMock(side_effect=SystemExit)
    monkeypatch.setattr('hive.indexer.blocks.os._exit', exits)

    Blocks.process_multi_sql_pipelined(1, 10)
    with pytest.raises(SystemExit):
        Blocks.process_multi_sql_pipelined(11, 20)

    exits.assert_called_once_with(1)
    assert pipeline.events == [('A', 1), 'handoff', ('A', 11)], 'Stage B of the first batch never ran'
    held.set()
    pipeline.gate(1).set()


@pytest.mark.parametrize('handoff_tables', [True, False])
def test_stage_a_truncates_its_tables_before_its_load_and_keeps_what_it_staged_for_the_handoff(
    monkeypatch: pytest.MonkeyPatch, handoff_tables: bool
) -> None:
    statements: list[str] = []
    db = MagicMock()
    db.query_no_return.side_effect = lambda sql, **kwargs: statements.append(sql)

    def query_all(sql: str) -> list[Any]:
        statements.append(sql)
        return []

    db.query_all.side_effect = query_all
    monkeypatch.setattr(Blocks, '_handoff_tables', handoff_tables)
    monkeypatch.setattr(Blocks, '_since_stage_reset', {'A': [0, 0], 'B': [0, 0]})
    monkeypatch.setattr(Community, 'start_block', 37500000)

    Blocks._run_stage_a(db, 4500001, 4510000, None, None, {})  # 10,000 blocks: a reset is due

    resets = [i for i, sql in enumerate(statements) if 'reset_' in sql]
    load = next(i for i, sql in enumerate(statements) if 'load_ops_staging(' in sql)
    if handoff_tables:
        assert [statements[i] for i in resets] == ['SELECT hivemind_app.reset_stage_a_staging_tables()']
        assert resets[0] < load, 'a reset after the load would truncate the batch before its handoff'
    else:
        assert resets == [], 'without handoff tables Stage B resets every staging table, after the batch'
    assert statements[-2:] == [
        'UPDATE hivemind_app._batch_queue SET stage_a_applied = TRUE WHERE first_block = 4500001',
        'COMMIT',
    ]


def test_a_deadlocked_phase_4_task_runs_again_alone(monkeypatch: pytest.MonkeyPatch) -> None:
    tasks = {name: MagicMock(name=name) for name in ('reblogs', 'follows', 'payouts')}
    tasks['payouts'].query_all_raw.side_effect = [
        psycopg2.extensions.TransactionRollbackError('deadlock detected'),
        [(None,)],
    ]
    monkeypatch.setattr(Reblog, 'db', tasks['reblogs'])
    monkeypatch.setattr(Follow, 'db', tasks['follows'])
    monkeypatch.setattr(Posts, 'db', tasks['payouts'])
    monkeypatch.setattr(Blocks, '_process_votes_massive', MagicMock())
    monkeypatch.setattr(Blocks, '_handoff_tables', False)
    monkeypatch.setattr(PostDataCache, 'flush', MagicMock())
    monkeypatch.setattr(DbState, 'are_indexes_enabled', MagicMock(return_value=False))
    monkeypatch.setattr(DbState, 'run_boundary_vacuums', MagicMock())
    monkeypatch.setattr('hive.indexer.blocks.sleep', lambda _: None)
    db = MagicMock()
    db.query_one.return_value = 2**31 - 1  # no notification flush

    Blocks._run_stage_b(db, 4500001, 4510000, [], True, {}, 4000000)

    assert tasks['reblogs'].query_all_raw.call_count == 1, 'a committed reblogs task would draw hive_reblogs ids again'
    assert tasks['follows'].query_all_raw.call_count == 1
    assert tasks['payouts'].query_all_raw.call_count == 2
    assert tasks['payouts'].query_all_raw.call_args.args == (
        'SELECT hivemind_app.process_payouts_from_staging(4000000)',
    )


def test_the_stage_a_committed_kill_point_needs_pipelining(monkeypatch: pytest.MonkeyPatch) -> None:
    conf = MagicMock()
    conf.get.side_effect = {
        'massive_vote_workers': 1,
        'massive_sync_pipelined': False,
        'test_pipeline_kill': 'stage_a_committed:1',
    }.get
    with pytest.raises(ValueError, match='needs --massive-sync-pipelined'):
        Blocks.setup(conf)
    monkeypatch.setattr(Blocks, '_kill_point', None)


def test_a_replay_runs_stage_b_only_for_a_batch_whose_stage_a_committed_then_the_next_whole() -> None:
    statements: list[str] = []
    db = MagicMock()
    db.query_no_return.side_effect = statements.append
    db.query_all.return_value = [(1, 10, True), (11, 20, False)]
    sync = SyncHiveDb.__new__(SyncHiveDb)
    sync._db = db
    calls = MagicMock()

    with (
        patch.object(Blocks, 'setup_own_db_access'),
        patch.object(Blocks, 'set_end_of_sync_lib'),
        patch.object(Blocks, 'set_stage_b_handoff', calls.handoff),
        patch.object(Blocks, 'process_stage_b_of_batch', calls.stage_b),
        patch.object(Blocks, 'process_multi_sql', calls.whole),
        patch.object(Blocks, '_pipelined', True),
    ):
        sync._replay_crashed_batch()

    assert 'ORDER BY first_block' in db.query_all.call_args.args[0]
    assert [c[0] for c in calls.mock_calls] == ['handoff', 'stage_b', 'whole']
    calls.handoff.assert_called_once_with(db, True)
    calls.stage_b.assert_called_once_with(1, 10)
    calls.whole.assert_called_once_with(11, 20)
    assert [s for s in statements if 'DELETE' in s] == [
        'DELETE FROM hivemind_app._batch_queue WHERE first_block = 1',
        'DELETE FROM hivemind_app._batch_queue WHERE first_block = 11',
    ]
