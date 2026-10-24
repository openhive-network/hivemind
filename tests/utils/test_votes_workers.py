"""The massive-sync votes phase across several upsert connections (Blocks + Votes)."""

import re
import threading
from collections.abc import Iterator
from unittest.mock import MagicMock

import psycopg2.errors
import psycopg2.extensions
import pytest

from hive.indexer.blocks import Blocks
from hive.indexer.db_adapter_holder import DbLiveContextHolder
from hive.indexer.votes import Votes

_PARTITION = re.compile(r'upsert_votes_partition\((\d+), (\d+)\)')


class _FakeDb:
    """Records (name, sql) into a shared log; a partition upsert returns 10 + its partition number."""

    def __init__(
        self,
        name: str,
        log: list[tuple[str, str]],
        lock: threading.Lock,
        failures: list[Exception] | None = None,
    ) -> None:
        self.name = name
        self._log = log
        self._lock = lock
        self._failures = failures if failures is not None else []
        self.closed = False

    def _record(self, sql: str) -> None:
        with self._lock:
            self._log.append((self.name, sql))

    def query_no_return(self, sql: str) -> None:
        self._record(sql)

    def query_all_raw(self, sql: str) -> list[tuple[int]]:
        self._record(sql)
        if self._failures:
            raise self._failures.pop(0)
        if match := _PARTITION.search(sql):
            return [(10 + int(match.group(1)),)]
        if 'process_votes_from_staging' in sql:
            return [(7,)]
        return []

    def close(self) -> None:
        self.closed = True


class _Workers:
    """Installs fake connections as Votes' upsert connections; `log` is their shared statement log."""

    def __init__(self, monkeypatch: pytest.MonkeyPatch) -> None:
        self._monkeypatch = monkeypatch
        self._lock = threading.Lock()
        self.log: list[tuple[str, str]] = []

    def __call__(self, count: int, failures: dict[int, list[Exception]] | None = None) -> list[_FakeDb]:
        dbs = [_FakeDb(f'db{i}', self.log, self._lock, (failures or {}).get(i)) for i in range(count)]
        self._monkeypatch.setattr(Votes, 'db', dbs[0])
        self._monkeypatch.setattr(Votes, '_worker_dbs', dbs[1:])
        return dbs


@pytest.fixture
def workers(monkeypatch: pytest.MonkeyPatch) -> Iterator[_Workers]:
    monkeypatch.setattr('hive.indexer.blocks.sleep', lambda _: None)
    yield _Workers(monkeypatch)


def test_partitions_run_after_the_prepared_batch_commits(workers: _Workers) -> None:
    workers(3)

    assert Blocks._process_votes_massive() == 10 + 11 + 12

    log = workers.log
    assert log[:3] == [
        ('db0', 'START TRANSACTION'),
        ('db0', 'SELECT hivemind_app.prepare_votes_from_staging()'),
        ('db0', 'COMMIT'),
    ]
    upserts = {(name, sql) for name, sql in log[3:] if 'upsert_votes_partition' in sql}
    assert upserts == {(f'db{i}', f'SELECT hivemind_app.upsert_votes_partition({i}, 3)') for i in range(3)}
    for i in range(3):
        assert [sql for name, sql in log[3:] if name == f'db{i}'][-1] == 'COMMIT'


def test_one_worker_runs_the_single_connection_function(workers: _Workers) -> None:
    workers(1)

    assert Blocks._process_votes_massive() == 7
    assert [sql for _, sql in workers.log] == [
        'START TRANSACTION',
        f'SELECT hivemind_app.process_votes_from_staging({Blocks._last_safe_cashout_block})',
        'COMMIT',
    ]


def test_a_deadlocked_partition_retries_every_partition_but_not_the_prepare(workers: _Workers) -> None:
    workers(3, failures={1: [psycopg2.extensions.TransactionRollbackError('deadlock detected')]})

    assert Blocks._process_votes_massive() == 10 + 11 + 12

    sqls = [sql for _, sql in workers.log]
    assert sqls.count('SELECT hivemind_app.prepare_votes_from_staging()') == 1
    assert sqls.count('SELECT hivemind_app.upsert_votes_partition(0, 3)') == 2
    assert sqls.count('SELECT hivemind_app.upsert_votes_partition(1, 3)') == 2
    assert ('db1', 'ROLLBACK') in workers.log


def test_a_failing_partition_fails_the_batch_with_its_error(workers: _Workers) -> None:
    workers(2, failures={1: [psycopg2.errors.UniqueViolation('duplicate key')]})

    with pytest.raises(psycopg2.errors.UniqueViolation, match='duplicate key'):
        Blocks._process_votes_massive()
    assert [sql for _, sql in workers.log].count('SELECT hivemind_app.upsert_votes_partition(1, 2)') == 1


@pytest.mark.parametrize(('live', 'opened'), [(False, ['Votes_1', 'Votes_2', 'Votes_3']), (True, [])])
def test_worker_connections_open_in_massive_sync_only(
    monkeypatch: pytest.MonkeyPatch, live: bool, opened: list[str]
) -> None:
    monkeypatch.setattr(DbLiveContextHolder, '_live_context', live)
    monkeypatch.setattr(Votes, '_worker_dbs', [])
    monkeypatch.setattr(Votes, 'db', None)
    shared = MagicMock()
    worker_dbs: list[MagicMock] = []

    def clone(name: str) -> MagicMock:
        worker_dbs.append(MagicMock(name=name))
        return worker_dbs[-1]

    shared.clone.side_effect = clone

    Votes.setup_worker_db_access(shared, 4)

    assert [call.args[0] for call in shared.clone.call_args_list] == opened
    Votes.close_own_db_access()
    assert Votes._worker_dbs == []
    for db in worker_dbs:
        db.close.assert_called_once_with()
