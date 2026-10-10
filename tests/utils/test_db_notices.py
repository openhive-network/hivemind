"""Server messages (NOTICE/WARNING/...) raised on a Db connection reach the log, all of them."""

import logging
from collections.abc import Iterator
from contextlib import contextmanager
from unittest.mock import patch

import pytest

from hive.db.adapter import Db


class _FakeConnection:
    def __init__(self) -> None:
        self.notices: list[str] = []
        self.autocommit = False
        self.closed = False

    def close(self) -> None:
        self.closed = True


@contextmanager
def _fake_connect() -> Iterator[None]:
    with (
        patch('hive.db.adapter.psycopg2.connect', side_effect=lambda *a, **kw: _FakeConnection()),
        patch('hive.db.adapter.register_default_jsonb'),
    ):
        yield


@pytest.fixture
def db() -> Iterator[Db]:
    with _fake_connect():
        yield Db('postgresql://hivemind@localhost/haf_block_log', 'root')


def _adapter_records(caplog: pytest.LogCaptureFixture) -> list[tuple[int, str]]:
    return [(r.levelno, r.getMessage()) for r in caplog.records if r.name == 'hive.db.adapter']


def test_handler_is_installed_on_connect(db: Db, caplog: pytest.LogCaptureFixture) -> None:
    caplog.set_level(logging.INFO, logger='hive.db.adapter')

    assert not isinstance(db._conn.notices, list)
    db._conn.notices.append('NOTICE:  hello\n')

    assert _adapter_records(caplog) == [(logging.INFO, '[root] NOTICE:  hello')]


def test_messages_are_logged_at_their_severity_with_connection_name(db: Db, caplog: pytest.LogCaptureFixture) -> None:
    caplog.set_level(logging.DEBUG, logger='hive.db.adapter')

    db._conn.notices.append('NOTICE:  Waiting for HAF instance to be ready\n')
    db._conn.notices.append('WARNING:  PROFILE hivemind_app SLOW_PROCESSING\n')
    db._conn.notices.append('LOG:  duration: 1.0 ms\n')
    db._conn.notices.append('DEBUG1:  detail\n')

    assert _adapter_records(caplog) == [
        (logging.INFO, '[root] NOTICE:  Waiting for HAF instance to be ready'),
        (logging.WARNING, '[root] WARNING:  PROFILE hivemind_app SLOW_PROCESSING'),
        (logging.INFO, '[root] LOG:  duration: 1.0 ms'),
        (logging.DEBUG, '[root] DEBUG1:  detail'),
    ]


def test_more_than_fifty_messages_are_all_logged(db: Db, caplog: pytest.LogCaptureFixture) -> None:
    caplog.set_level(logging.INFO, logger='hive.db.adapter')

    for i in range(60):
        db._conn.notices.append(f'NOTICE:  message {i}\n')

    assert [m for _, m in _adapter_records(caplog)] == [f'[root] NOTICE:  message {i}' for i in range(60)]


def test_reconnect_and_clones_install_handler(db: Db, caplog: pytest.LogCaptureFixture) -> None:
    caplog.set_level(logging.INFO, logger='hive.db.adapter')
    with _fake_connect():
        db.reconnect()
        clone = db.clone('worker')
        impersonated = db.impersonated_clone('owner', 'haf_admin')

    db._conn.notices.append('NOTICE:  after reconnect\n')
    clone._conn.notices.append('NOTICE:  on clone\n')
    impersonated._conn.notices.append('NOTICE:  on impersonated clone\n')

    assert [m for _, m in _adapter_records(caplog)] == [
        '[root] NOTICE:  after reconnect',
        '[worker] NOTICE:  on clone',
        '[owner] NOTICE:  on impersonated clone',
    ]


def test_routine_ddl_notices_go_to_debug(db: Db, caplog: pytest.LogCaptureFixture) -> None:
    caplog.set_level(logging.DEBUG, logger='hive.db.adapter')
    db._conn.notices.append('NOTICE:  table "_final_actions" does not exist, skipping\n')
    db._conn.notices.append('NOTICE:  type reference hivemind_app.hive_posts.id%TYPE converted to integer\n')
    db._conn.notices.append('NOTICE:  drop cascades to 3 other objects\n')
    db._conn.notices.append('NOTICE:  drop cascades to 1 other object\n')
    db._conn.notices.append('NOTICE:  Index hive_posts_idx created in 1.234 seconds\n')
    db._conn.notices.append('WARNING:  table "x" does not exist, skipping\n')
    assert [level for level, _ in _adapter_records(caplog)] == [
        logging.DEBUG,
        logging.DEBUG,
        logging.DEBUG,
        logging.DEBUG,
        logging.INFO,
        logging.WARNING,
    ]
