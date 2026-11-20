"""Every start states in one line whether full-text search works, and why not (#488).

A database whose pg_search could not be created used to run with find_text and
find_similar off and nothing in its start-up log; the failed CREATE EXTENSION
itself logged no reason.
"""

import dataclasses
import logging
from unittest.mock import MagicMock, patch

import psycopg2.errors
import pytest

import hive.db.schema as schema_module
from hive.db.db_state import DbState
from hive.db.schema import SearchStatus, _try_create_extension, bm25_index_sql, search_status

_READY = SearchStatus(
    package_available=True,
    preloaded=True,
    extension_installed=True,
    function_present=True,
    index_present=True,
    index_valid=True,
)


def _start(
    status: SearchStatus, caplog: pytest.LogCaptureFixture, initial_sync: bool = False
) -> list[logging.LogRecord]:
    """Run the start-up search check against a fake status; return its log records."""
    with (
        patch('hive.db.db_state.search_status', return_value=status),
        patch.object(DbState, 'db', staticmethod(MagicMock)),
        patch.object(DbState, 'is_initial_sync', classmethod(lambda cls: initial_sync)),
        patch.object(schema_module, 'pg_search_available', not status.usable),
        caplog.at_level(logging.INFO, logger='hive.db.db_state'),
    ):
        DbState._log_search_status()
        assert schema_module.pg_search_available is status.usable
    return [r for r in caplog.records if r.name == 'hive.db.db_state']


@pytest.mark.parametrize(
    ('missing', 'reason'),
    [
        ({'package_available': False, 'preloaded': False, 'extension_installed': False}, 'no pg_search package'),
        ({'preloaded': False, 'extension_installed': False}, 'not in shared_preload_libraries'),
        ({'preloaded': False}, 'not in shared_preload_libraries'),
        ({'extension_installed': False, 'function_present': False}, 'extension is not installed'),
        ({'function_present': False, 'index_present': False}, 'is_top_level_post is missing'),
        ({'index_present': False, 'index_valid': False}, 'hive_post_data_bm25_idx is missing'),
        ({'index_valid': False}, 'hive_post_data_bm25_idx is INVALID'),
    ],
)
def test_search_off_warns_with_its_reason_and_remedy(
    missing: dict[str, bool], reason: str, caplog: pytest.LogCaptureFixture
) -> None:
    records = _start(dataclasses.replace(_READY, **missing), caplog)

    assert [r.levelno for r in records] == [logging.WARNING]
    message = records[0].getMessage()
    assert reason in message
    assert 'full-text search' in message
    assert 'replay hivemind' in message and '#488' in message
    assert 'upgrade_schema' not in message


def test_missing_index_during_initial_sync_is_info(caplog: pytest.LogCaptureFixture) -> None:
    records = _start(dataclasses.replace(_READY, index_present=False, index_valid=False), caplog, initial_sync=True)

    assert [r.levelno for r in records] == [logging.INFO]
    assert 'end of the initial sync' in records[0].getMessage()


def test_ready_search_logs_one_info_line(caplog: pytest.LogCaptureFixture) -> None:
    records = _start(_READY, caplog)

    assert [r.levelno for r in records] == [logging.INFO]
    assert 'ready' in records[0].getMessage()


@pytest.mark.parametrize(
    ('row', 'usable'),
    [
        ((True, True, True, True, True, True), True),
        ((True, True, True, True, False, False), True),
        ((True, False, True, True, True, True), True),
        ((True, True, True, False, False, False), False),
        ((True, True, False, False, False, False), False),
    ],
)
def test_search_status_maps_the_query_result(row: tuple[bool, ...], usable: bool) -> None:
    db = MagicMock()
    db.query_all.return_value = [row]

    status = search_status(db)

    assert dataclasses.astuple(status) == row
    assert status.usable is usable
    sql = db.query_all.call_args.args[0]
    assert 'shared_preload_libraries' not in sql
    assert "LIKE 'paradedb.%'" in sql
    assert 'indisvalid' in sql


def test_failed_create_extension_logs_the_first_line_of_the_error(caplog: pytest.LogCaptureFixture) -> None:
    db = MagicMock()
    db.query.side_effect = psycopg2.errors.FeatureNotSupported(
        'pg_search must be loaded via shared_preload_libraries\nCONTEXT:  SQL statement "LOAD"'
    )

    with caplog.at_level(logging.WARNING, logger='hive.db.schema'):
        assert _try_create_extension(db, 'pg_search') is False

    messages = [r.getMessage() for r in caplog.records if r.levelno == logging.WARNING]
    assert messages == ['Could not create extension pg_search: pg_search must be loaded via shared_preload_libraries']


def test_setup_and_finalization_build_the_same_index() -> None:
    sql = bm25_index_sql()

    assert sql.startswith(
        'CREATE INDEX IF NOT EXISTS hive_post_data_bm25_idx ON hivemind_app.hive_post_data USING bm25'
    )
    assert '"title": {"record": "position"}' in sql
    assert sql.endswith('WHERE hivemind_app.is_top_level_post(id)')
