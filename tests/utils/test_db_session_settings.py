"""Every Db connection, however it is opened, has synchronized seq scans off before its first query."""

from collections.abc import Iterator
from contextlib import contextmanager
from unittest.mock import patch

import pytest

from hive.db.adapter import Db


class _RecordingCursor:
    def __init__(self, executed: list[str]) -> None:
        self._executed = executed

    def __enter__(self) -> _RecordingCursor:
        return self

    def __exit__(self, *exc: object) -> None:
        return None

    def execute(self, sql: str) -> None:
        self._executed.append(sql)


class _FakeConnection:
    def __init__(self, dsn: str) -> None:
        self.dsn = dsn
        self.executed: list[str] = []
        self.notices: list[str] = []
        self.autocommit = False
        self.closed = False

    def cursor(self) -> _RecordingCursor:
        return _RecordingCursor(self.executed)

    def close(self) -> None:
        self.closed = True


@contextmanager
def _fake_connect() -> Iterator[None]:
    with (
        patch('hive.db.adapter.psycopg2.connect', side_effect=lambda dsn, **kw: _FakeConnection(dsn)),
        patch('hive.db.adapter.register_default_jsonb'),
    ):
        yield


@pytest.fixture
def db() -> Iterator[Db]:
    with _fake_connect():
        yield Db('postgresql://hivemind@localhost/haf_block_log', 'root')


def test_new_connection_turns_synchronized_scans_off_before_any_query(db: Db) -> None:
    assert db._conn.executed == ['SET synchronize_seqscans = off']
    assert db._conn.autocommit is True


def test_reconnects_and_clones_turn_synchronized_scans_off(db: Db) -> None:
    with _fake_connect():
        db.reconnect()
        clone = db.clone('logged_convert_hive_votes')
        impersonated = db.impersonated_clone('owner', 'haf_admin')

    for conn in (db._conn, clone._conn, impersonated._conn):
        assert conn.executed == ['SET synchronize_seqscans = off']
    assert 'user=haf_admin' in impersonated._conn.dsn
