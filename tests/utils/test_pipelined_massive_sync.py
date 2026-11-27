"""Pipelined massive sync: a batch's Stage B runs on its own thread beside the next batch's Stage A."""

import logging
import sys
import threading
from collections.abc import Iterator
from concurrent.futures import ThreadPoolExecutor
from typing import Any
from unittest.mock import MagicMock, patch

import psycopg2
import psycopg2.errors
import pytest

import hive.conf
from hive.conf import Conf
from hive.db.db_state import DbState
from hive.indexer.blocks import Blocks
from hive.indexer.community import Community
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.indexer.follow import Follow
from hive.indexer.notification_cache import FollowNotificationCache, PostNotificationCache, ReblogNotificationCache
from hive.indexer.payouts import Payouts
from hive.indexer.post_data_cache import PostDataCache
from hive.indexer.reblog import Reblog
from hive.indexer.sync import SyncHiveDb
from hive.indexer.votes import Votes


class _Pipeline:
    """Stands in for the stages' SQL: records the order of Stage A, the handoffs and Stage B."""

    def __init__(self) -> None:
        self.events: list[tuple[str, int] | str] = []
        self.gates: dict[int, threading.Event] = {}
        self.failing: set[int] = set()
        self.cashout: dict[int, int] = {}
        self.deferred: dict[int, bool] = {}
        self.stage_b_db = _named_db('stage_b_instance')
        self.common_db = _named_db('massive_instance')
        self.common_db.query_one.side_effect = self.query_one
        self.lock_waits: dict[str, float] = {}

    def query_one(self, sql: str) -> int:
        assert sql == 'SELECT hivemind_app.apply_deferred_payouts()', sql
        self.events.append('apply_deferred')
        return 2

    def total(self, names: list[str]) -> float:
        """The lock wait sampler's totals."""
        return sum(self.lock_waits.get(name, 0.0) for name in set(names))

    def gate(self, first_block: int) -> threading.Event:
        return self.gates.setdefault(first_block, threading.Event())

    def stage_a(
        self, db: Any, first: int, last: int, prefetch: Any, next_range: Any, phase_times: dict[str, float]
    ) -> tuple[list[Any], bool, None]:
        self.events.append(('A', first))
        phase_times['posts'] = 0.0
        self.lock_waits['hivemind_massive_instance'] = self.lock_waits.get('hivemind_massive_instance', 0.0) + 0.25
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
        defer_locked_payouts: bool = False,
    ) -> dict[str, float]:
        assert db is self.stage_b_db, 'Stage B runs on its own connection'
        assert self.gate(first).wait(5), f'Stage B of {first} was never released'
        if first in self.failing:
            raise RuntimeError(f'Stage B of {first} failed')
        self.cashout[first] = cashout
        self.deferred[first] = defer_locked_payouts
        self.lock_waits['hivemind_Payouts_1'] = self.lock_waits.get('hivemind_Payouts_1', 0.0) + 1.5
        self.lock_waits['hivemind_Follow'] = self.lock_waits.get('hivemind_Follow', 0.0) + 0.125
        self.events.append(('B', first))
        return {'votes_payouts': 0.25, 'follows': 0.125}

    def hand_off(self, db: Any) -> None:
        self.events.append('handoff')

    def deleted_rows(self) -> list[str]:
        return [c.args[0] for c in self.stage_b_db.query_no_return.call_args_list if 'DELETE' in c.args[0]]


def _named_db(name: str) -> MagicMock:
    db = MagicMock(name=name)
    db.name = name
    return db


@pytest.fixture
def pipeline(monkeypatch: pytest.MonkeyPatch) -> Iterator[_Pipeline]:
    p = _Pipeline()
    monkeypatch.setattr(Blocks, '_lock_waits', p)
    for holder in (Votes, Payouts, Reblog, Follow, PostDataCache):
        monkeypatch.setattr(holder, 'db', _named_db(holder.__name__))
    for cache in (PostNotificationCache, FollowNotificationCache, ReblogNotificationCache):
        monkeypatch.setattr(cache, 'db', None)
    monkeypatch.setattr(Votes, '_worker_dbs', [])
    monkeypatch.setattr(Payouts, '_worker_dbs', [_named_db('Payouts_1')])
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
    monkeypatch.setattr(DbAdapterHolder, '_block_processing_thread_sync_db', p.common_db)
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
    assert pipeline.events == [('A', 1), 'apply_deferred', 'handoff']

    monkeypatch.setattr(Blocks, '_last_safe_cashout_block', 200)  # set_end_of_sync_lib for the next batch
    second = _in_thread(Blocks.process_multi_sql_pipelined, 11, 20)
    for _ in range(100):
        if ('A', 11) in pipeline.events:
            break
        threading.Event().wait(0.01)
    threading.Event().wait(0.05)
    assert pipeline.events == [('A', 1), 'apply_deferred', 'handoff', ('A', 11)], (
        'no handoff while Stage B of the batch before runs'
    )
    assert not second.done()

    pipeline.gate(1).set()
    second.result(timeout=5)
    pipeline.gate(11).set()
    Blocks.wait_for_stage_b()

    assert pipeline.events == [
        ('A', 1),
        'apply_deferred',
        'handoff',
        ('A', 11),
        ('B', 1),
        'apply_deferred',
        'handoff',
        ('B', 11),
    ], "the payouts Stage B of 1-10 deferred are applied before Stage B of 11-20 starts"
    assert pipeline.cashout == {1: 100, 11: 200}, 'each Stage B pays out as of its own batch'
    assert pipeline.deferred == {1: True, 11: True}, 'beside a Stage A, Stage B defers the payouts of held posts'
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
    assert second_a.endswith(' posts=0.000'), 'the A line names its phases'
    assert ' deferred_payouts=2 ' in second_a, 'the A line counts the deferred payouts it applied'
    assert ' lock_wait=0.250 ' in second_a, "the A line holds its own connection's lock waits"
    (second_b,) = (t for t in timing if 'blocks=11-20 stage=B' in t)
    assert second_b.endswith(' votes_payouts=0.250 follows=0.125'), 'the B line names its lanes'
    assert 'posts=' not in second_b, "the B line leaves out Stage A's phases"
    assert ' lock_wait=1.625 lock_wait_votes_payouts=1.500 lock_wait_reblogs=0.000 lock_wait_follows=0.125 ' in (
        second_b
    ), "the B line holds its connections' lock waits during its own run, in all and per lane"


def test_a_failed_stage_b_stops_the_next_batch_before_its_handoff_and_keeps_its_row(pipeline: _Pipeline) -> None:
    pipeline.failing.add(1)
    pipeline.gate(1).set()

    Blocks.process_multi_sql_pipelined(1, 10)
    with pytest.raises(RuntimeError, match='Stage B of 1 failed'):
        Blocks.process_multi_sql_pipelined(11, 20)

    assert pipeline.events == [('A', 1), 'apply_deferred', 'handoff', ('A', 11)]
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
    assert pipeline.events == [('A', 1), 'apply_deferred', 'handoff', ('A', 11)], 'Stage B of the first batch never ran'
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


class _Conn:
    """A connection recording its statements into a shared log; `on_sql` may block or raise for one."""

    def __init__(self, name: str, log: list[tuple[str, str]], on_sql: Any = None) -> None:
        self.name = name
        self._log = log
        self._on_sql = on_sql

    def query_no_return(self, sql: str, **kwargs: Any) -> None:
        self._log.append((self.name, sql))
        if self._on_sql is not None and sql not in ('START TRANSACTION', 'COMMIT', 'ROLLBACK'):
            self._on_sql(self.name, sql)

    def query_all_raw(self, sql: str) -> list[tuple[int]]:
        self.query_no_return(sql)
        return [(1,)]


@pytest.fixture
def stage_b(monkeypatch: pytest.MonkeyPatch) -> Any:
    """Installs recording connections for Stage B's phases; returns the function installing them."""
    monkeypatch.setattr(Blocks, '_handoff_tables', False)
    monkeypatch.setattr(Blocks, '_kill_point', None)
    monkeypatch.setattr(PostDataCache, 'flush', MagicMock())
    monkeypatch.setattr(DbState, 'are_indexes_enabled', MagicMock(return_value=False))
    monkeypatch.setattr(DbState, 'run_boundary_vacuums', MagicMock())
    monkeypatch.setattr('hive.indexer.blocks.sleep', lambda _: None)

    def install(log: list[tuple[str, str]], on_sql: Any = None, votes: int = 2, payouts: int = 3) -> None:
        def conns(prefix: str, count: int) -> list[_Conn]:
            return [_Conn(f'{prefix}{i}', log, on_sql) for i in range(count)]

        vote_dbs, payout_dbs = conns('votes', votes), conns('payouts', payouts)
        monkeypatch.setattr(Votes, 'db', vote_dbs[0])
        monkeypatch.setattr(Votes, '_worker_dbs', vote_dbs[1:])
        monkeypatch.setattr(Payouts, 'db', payout_dbs[0])
        monkeypatch.setattr(Payouts, '_worker_dbs', payout_dbs[1:])
        monkeypatch.setattr(Reblog, 'db', _Conn('reblogs', log, on_sql))
        monkeypatch.setattr(Follow, 'db', _Conn('follows', log, on_sql))

    return install


def _stage_b_db() -> MagicMock:
    db = MagicMock()
    db.query_one.return_value = 2**31 - 1  # no notification flush
    return db


def _ran(log: list[tuple[str, str]], name: str) -> list[str]:
    return [sql for conn, sql in log if conn == name and sql not in ('START TRANSACTION', 'COMMIT')]


def test_a_deadlocked_phase_4_task_runs_again_alone(stage_b: Any) -> None:
    log: list[tuple[str, str]] = []
    deadlocked: list[str] = []

    def on_sql(name: str, sql: str) -> None:
        if name == 'follows' and not deadlocked:
            deadlocked.append(sql)
            raise psycopg2.extensions.TransactionRollbackError('deadlock detected')

    stage_b(log, on_sql)

    Blocks._run_stage_b(_stage_b_db(), 4500001, 4510000, [], True, {}, 4000000)

    follows = 'SELECT * FROM hivemind_app.process_follows_for_blocks(4500001, 4510000)'
    assert _ran(log, 'follows') == [follows, 'ROLLBACK', follows]
    assert _ran(log, 'reblogs') == ['SELECT hivemind_app.process_reblogs_from_staging(4510000)'], (
        'a committed reblogs task would draw hive_reblogs ids again'
    )
    assert _ran(log, 'votes0') == [
        'SELECT hivemind_app.prepare_votes_from_staging()',
        'SELECT hivemind_app.upsert_votes_partition(0, 2)',
    ]
    assert len(_ran(log, 'payouts0')) == 1


def test_the_payouts_run_in_partitions_after_the_votes_and_beside_reblogs_and_follows(stage_b: Any) -> None:
    log: list[tuple[str, str]] = []
    votes_started = threading.Event()

    def on_sql(name: str, sql: str) -> None:
        if 'prepare_votes_from_staging' in sql:
            votes_started.set()
        if name in ('reblogs', 'follows') and not votes_started.wait(5):
            raise RuntimeError(f'{name} ran only after the votes lane had ended')

    stage_b(log, on_sql)

    lane_times = Blocks._run_stage_b(_stage_b_db(), 4500001, 4510000, [], True, {}, 4000000)

    sqls = [sql for _, sql in log]
    payouts = [(conn, sql) for conn, sql in log if 'process_payouts_from_staging' in sql]
    assert sorted(payouts) == [
        (f'payouts{i}', f'SELECT hivemind_app.process_payouts_from_staging(4000000, {i}, 3)') for i in range(3)
    ]
    last_vote = max(i for i, sql in enumerate(sqls) if 'upsert_votes_partition' in sql)
    first_payout = min(i for i, sql in enumerate(sqls) if 'process_payouts_from_staging' in sql)
    assert last_vote < first_payout, 'the payouts run once the votes have been written'
    assert set(lane_times) == {
        'votes_prepare',
        'votes_upsert',
        'payouts',
        'votes_payouts',
        'reblogs',
        'follows',
        'account_updates',
    }


def test_one_payout_connection_runs_the_whole_payouts_and_retries_a_deadlock(stage_b: Any) -> None:
    log: list[tuple[str, str]] = []
    failures = [psycopg2.extensions.TransactionRollbackError('deadlock detected')]

    def on_sql(name: str, sql: str) -> None:
        if 'process_payouts_from_staging' in sql and failures:
            raise failures.pop()

    stage_b(log, on_sql, votes=1, payouts=1)
    deadlocks = Blocks._deadlocks['B']

    Blocks._run_stage_b(_stage_b_db(), 4500001, 4510000, [], True, {}, 4000000)

    assert _ran(log, 'payouts0') == [
        'SELECT hivemind_app.process_payouts_from_staging(4000000)',
        'ROLLBACK',
        'SELECT hivemind_app.process_payouts_from_staging(4000000)',
    ]
    assert Blocks._deadlocks['B'] == deadlocks + 1


@pytest.mark.parametrize(
    ('payouts', 'calls'),
    [(3, [(4000000, i, 3) for i in range(3)]), (1, [(4000000, 0, 1)])],
    ids=['partitions', 'one-connection'],
)
def test_stage_b_beside_a_stage_a_defers_the_payouts_of_the_posts_another_transaction_holds(
    stage_b: Any, payouts: int, calls: list[tuple[int, int, int]]
) -> None:
    log: list[tuple[str, str]] = []
    stage_b(log, payouts=payouts)

    Blocks._run_stage_b(_stage_b_db(), 4500001, 4510000, [], True, {}, 4000000, defer_locked_payouts=True)

    assert sorted(sql for _, sql in log if 'process_payouts_from_staging' in sql) == [
        f'SELECT hivemind_app.process_payouts_from_staging({c}, {p}, {n}, TRUE)' for c, p, n in calls
    ]


@pytest.mark.parametrize('entry', ['process_multi_sql', 'process_stage_b_of_batch'])
def test_a_stage_b_run_alone_applies_the_deferred_payouts_first(monkeypatch: pytest.MonkeyPatch, entry: str) -> None:
    events: list[str] = []
    db = MagicMock()

    def query_one(sql: str) -> Any:
        if 'apply_deferred_payouts' in sql:
            events.append('apply_deferred')
            return 0
        return 4510000 if 'prefetch_ops_staging' in sql else True

    def stage_b(*args: Any, defer_locked_payouts: bool = False) -> dict[str, float]:
        assert not defer_locked_payouts, 'nothing runs beside it, so nothing is deferred'
        events.append('stage B')
        return {}

    db.query_one.side_effect = query_one
    db.query_all.return_value = []
    monkeypatch.setattr(DbAdapterHolder, '_block_processing_thread_sync_db', db)
    monkeypatch.setattr(Blocks, '_handoff_tables', False)
    monkeypatch.setattr(Blocks, '_run_stage_a', lambda *args: ([], True, None))
    monkeypatch.setattr(Blocks, '_run_stage_b', stage_b)
    monkeypatch.setattr(Blocks, '_log_phase_summary', lambda *args: None)

    getattr(Blocks, entry)(4500001, 4510000)

    assert events == ['apply_deferred', 'stage B'], (
        'the payouts a pipelined Stage B deferred come before the next rshares update and payouts'
    )


def test_a_failed_lane_fails_stage_b_once_the_other_lanes_have_ended(
    stage_b: Any, monkeypatch: pytest.MonkeyPatch
) -> None:
    log: list[tuple[str, str]] = []
    follows_done = threading.Event()

    def on_sql(name: str, sql: str) -> None:
        if name == 'reblogs':
            raise psycopg2.errors.UniqueViolation('duplicate key')
        if name == 'follows':
            threading.Event().wait(0.05)
            follows_done.set()

    stage_b(log, on_sql)
    flush = MagicMock()
    monkeypatch.setattr(PostDataCache, 'flush', flush)

    with pytest.raises(psycopg2.errors.UniqueViolation, match='duplicate key'):
        Blocks._run_stage_b(_stage_b_db(), 4500001, 4510000, [], True, {}, 4000000)

    assert follows_done.is_set()
    flush.assert_not_called()


def test_the_payouts_committed_kill_point_exits_after_the_payouts(
    stage_b: Any, monkeypatch: pytest.MonkeyPatch
) -> None:
    log: list[tuple[str, str]] = []
    stage_b(log)
    monkeypatch.setattr(Blocks, '_kill_point', ('payouts_committed', 4500001))
    exits = MagicMock(side_effect=SystemExit)
    monkeypatch.setattr('hive.indexer.blocks.os._exit', exits)

    with pytest.raises(SystemExit):
        Blocks._run_stage_b(_stage_b_db(), 4500001, 4510000, [], True, {}, 4000000)

    exits.assert_called_once_with(1)
    assert sorted(sql for _, sql in log if 'process_payouts_from_staging' in sql) == [
        f'SELECT hivemind_app.process_payouts_from_staging(4000000, {i}, 3)' for i in range(3)
    ]
    assert not any('process_account_updates_from_staging' in sql for _, sql in log)


@pytest.mark.parametrize(
    ('handoff_tables', 'load'),
    [(True, 'take_prefetched_ops_staging'), (False, 'load_ops_staging_from_prefetch')],
)
def test_stage_a_takes_the_prefetched_rows_by_rename_only_with_the_handoff_tables(
    monkeypatch: pytest.MonkeyPatch, handoff_tables: bool, load: str
) -> None:
    statements: list[str] = []
    db = MagicMock()
    db.query_no_return.side_effect = lambda sql, **kwargs: statements.append(sql)
    db.query_all.return_value = []
    prefetch = MagicMock()
    prefetch.take.return_value = 1.5
    monkeypatch.setattr(Blocks, '_handoff_tables', handoff_tables)
    monkeypatch.setattr(Blocks, '_since_stage_reset', {'A': [0, 0], 'B': [0, 0]})
    monkeypatch.setattr(Community, 'start_block', 37500000)

    assert Blocks._run_stage_a(db, 4500001, 4510000, prefetch, (4510001, 4520000), {})[2] == 1.5

    loads = [sql for sql in statements if 'ops_staging' in sql and 'reset_' not in sql]
    assert loads == [f'SELECT hivemind_app.{load}(4500001, 4510000)']
    prefetch.start.assert_called_once_with(4510001, 4520000)


def test_the_stage_a_committed_kill_point_needs_pipelining(monkeypatch: pytest.MonkeyPatch) -> None:
    conf = MagicMock()
    conf.get.side_effect = {
        'massive_vote_workers': 1,
        'massive_sync_pipelined': False,
        'test_pipeline_kill': 'stage_a_committed:1',
    }.get
    with pytest.raises(ValueError, match='needs pipelined massive sync'):
        Blocks.setup(conf)
    monkeypatch.setattr(Blocks, '_kill_point', None)


def _parsed_conf(monkeypatch: pytest.MonkeyPatch, request: pytest.FixtureRequest, *argv: str) -> Conf:
    monkeypatch.setattr(sys, 'argv', ['hive', 'sync', *argv])
    for name in ('_conf', '_vote_workers', '_pipelined', '_kill_point'):
        monkeypatch.setattr(Blocks, name, getattr(Blocks, name))
    monkeypatch.setattr(hive.conf, 'REPTRACKER_SCHEMA_NAME', hive.conf.REPTRACKER_SCHEMA_NAME)
    root = logging.getLogger()
    level = root.level
    request.addfinalizer(lambda: root.setLevel(level))
    conf = Conf()
    # configargparse keeps one parser per name; a fresh name gets a parser with no arguments added yet.
    conf.init_argparse(name=request.node.nodeid)
    return conf


@pytest.mark.parametrize(
    ('argv', 'env', 'pipelined'),
    [
        ((), None, True),
        (('--massive-sync-pipelined=false',), None, False),
        ((), 'false', False),
        (('--massive-sync-pipelined=true',), 'false', True),
    ],
    ids=['default', 'option-off', 'env-off', 'option-over-env'],
)
def test_massive_sync_is_pipelined_unless_turned_off(
    monkeypatch: pytest.MonkeyPatch,
    request: pytest.FixtureRequest,
    argv: tuple[str, ...],
    env: str | None,
    pipelined: bool,
) -> None:
    if env is None:
        monkeypatch.delenv('MASSIVE_SYNC_PIPELINED', raising=False)
    else:
        monkeypatch.setenv('MASSIVE_SYNC_PIPELINED', env)
    monkeypatch.delenv('TEST_PIPELINE_KILL', raising=False)
    conf = _parsed_conf(monkeypatch, request, *argv)
    monkeypatch.setattr(Blocks, '_pipelined', not pipelined)

    Blocks.setup(conf)

    assert Blocks.is_pipelined() is pipelined


def test_the_stage_a_committed_kill_point_runs_on_the_default(
    monkeypatch: pytest.MonkeyPatch, request: pytest.FixtureRequest
) -> None:
    monkeypatch.delenv('MASSIVE_SYNC_PIPELINED', raising=False)
    conf = _parsed_conf(monkeypatch, request, '--test-pipeline-kill=stage_a_committed:1')
    monkeypatch.setattr(Blocks, '_pipelined', False)

    Blocks.setup(conf)

    assert Blocks.is_pipelined() is True
    assert Blocks._kill_point == ('stage_a_committed', 1)


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
