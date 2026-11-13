"""Guard the table-schema check of install and sync.

A database records the table upgrade it has (schema.record_table_schema). An
install on an existing database whose record differs applies the upgrade; sync
refuses to start on it, before dropping any foreign key or index; an install
the HAF lock keeps out fails when it had work to do, naming the holders.
"""

import logging
from collections.abc import Iterator
from contextlib import contextmanager
from typing import Any
from unittest.mock import MagicMock, patch

import pytest

from hive.db.db_state import DbState, TableSchemaBehindError
from hive.db.schema import perform_db_upgrade, table_schema_digest
from hive.indexer.community import Community
from hive.indexer.sync import SyncHiveDb
from hive.version import GIT_REVISION

_STALE = 'f' * 64


class _Database:
    """A connection answering the queries of the table-schema check from the state it is given."""

    def __init__(
        self,
        schema_loaded: bool = True,
        recorded: str | None = None,
        runtime_revision: str = GIT_REVISION,
        missing_tables: tuple[str, ...] = (),
        lock_holders: str | None = None,
    ) -> None:
        self.schema_loaded = schema_loaded
        self.recorded = recorded
        self.runtime_revision = runtime_revision
        self.missing_tables = missing_tables
        self.lock_holders = lock_holders
        self.statements: list[str] = []
        self.clone = MagicMock(return_value=MagicMock())
        self.impersonated_clone = MagicMock(return_value=MagicMock())

    def query_one(self, sql: str, **kwargs: Any) -> Any:
        self.statements.append(sql)
        if 'pg_catalog.pg_tables' in sql:
            return 1 if self.schema_loaded else None
        if "to_regclass('hivemind_app.hive_table_schema')" in sql:
            return self.recorded is not None
        if 'upgrade_digest' in sql:
            return self.recorded
        if 'hivemind_git_rev' in sql:
            return self.runtime_revision
        if 'pg_locks' in sql:
            return self.lock_holders
        if 'pg_extension' in sql:
            return 0
        raise AssertionError(f'unexpected query: {sql}')

    def query_all(self, sql: str, **kwargs: Any) -> list[Any]:
        self.statements.append(sql)
        return [(0,)]

    def query_col(self, sql: str, tables: list[str], schema: str) -> list[str]:
        self.statements.append(sql)
        return [t for t in tables if t in self.missing_tables]

    def query_no_return(self, sql: str, **kwargs: Any) -> None:
        self.statements.append(sql)


@contextmanager
def _installer(database: _Database) -> Iterator[dict[str, MagicMock]]:
    mocks = {name: MagicMock() for name in ('setup', 'perform_db_upgrade', 'setup_runtime_code')}
    with (
        patch.object(DbState, 'db', staticmethod(lambda: database)),
        patch.multiple('hive.db.db_state', **mocks),
    ):
        yield mocks


def test_sync_refuses_a_schema_behind_the_code_before_touching_it() -> None:
    database = _Database(recorded=_STALE)
    with _installer(database) as mocks, pytest.raises(TableSchemaBehindError) as raised:
        DbState.initialize(enter_massive=True, schema_upgrade=False)

    assert 'upgrade_schema' in str(raised.value)
    assert _STALE[:12] in str(raised.value) and table_schema_digest()[:12] in str(raised.value)
    for mock in mocks.values():
        mock.assert_not_called()
    database.impersonated_clone.assert_not_called()


def test_sync_refuses_a_database_installed_before_the_record() -> None:
    with (
        _installer(_Database(recorded=None)),
        pytest.raises(TableSchemaBehindError, match='records table upgrade none'),
    ):
        DbState.initialize(enter_massive=True, schema_upgrade=False)


def test_sync_starts_on_a_current_schema() -> None:
    with _installer(_Database(recorded=table_schema_digest())) as mocks:
        DbState.initialize(enter_massive=True, schema_upgrade=False)

    mocks['perform_db_upgrade'].assert_not_called()
    mocks['setup_runtime_code'].assert_called_once()


def test_sync_installs_a_fresh_database() -> None:
    with _installer(_Database(schema_loaded=False)) as mocks:
        DbState.initialize(enter_massive=True, schema_upgrade=False)

    mocks['setup'].assert_called_once()
    mocks['perform_db_upgrade'].assert_not_called()


@pytest.mark.parametrize('recorded', [_STALE, None])
def test_build_schema_applies_a_pending_table_upgrade(recorded: str | None) -> None:
    with _installer(_Database(recorded=recorded)) as mocks:
        DbState.initialize(enter_massive=False, schema_upgrade=False)

    mocks['perform_db_upgrade'].assert_called_once()
    mocks['setup'].assert_not_called()
    mocks['setup_runtime_code'].assert_called_once()


def test_build_schema_leaves_a_current_table_schema() -> None:
    with _installer(_Database(recorded=table_schema_digest())) as mocks:
        DbState.initialize(enter_massive=False, schema_upgrade=False)

    mocks['perform_db_upgrade'].assert_not_called()
    mocks['setup_runtime_code'].assert_called_once()


def test_upgrade_schema_upgrades_a_current_table_schema() -> None:
    with _installer(_Database(recorded=table_schema_digest())) as mocks:
        DbState.initialize(enter_massive=False, schema_upgrade=True)

    mocks['perform_db_upgrade'].assert_called_once()


def test_upgrade_records_the_code_table_schema() -> None:
    admin_db = MagicMock()
    admin_db.query_one.return_value = False
    db = MagicMock()
    with patch('hive.db.schema.execute_sql_script'):
        perform_db_upgrade(db=db, admin_db=admin_db)

    recorded = [
        c.args[0]
        for c in db.query_no_return.call_args_list
        if 'INSERT INTO hivemind_app.hive_table_schema' in c.args[0]
    ]
    assert len(recorded) == 1 and f"VALUES ('{table_schema_digest()}')" in recorded[0], recorded
    admin_db.query_no_return.assert_not_called()


@pytest.mark.parametrize(
    ('database', 'expected'),
    [
        (_Database(schema_loaded=False), ['the hivemind schema is not installed']),
        (_Database(recorded=_STALE), ["hivemind's table schema is behind this code"]),
        (
            _Database(recorded=table_schema_digest(), runtime_revision='59a0ccf50'),
            ['the runtime code is of revision 59a0ccf50'],
        ),
        (
            _Database(recorded=None, runtime_revision='59a0ccf50'),
            ["hivemind's table schema is behind this code", 'the runtime code is of revision 59a0ccf50'],
        ),
        (_Database(recorded=table_schema_digest()), []),
    ],
)
def test_pending_install_work(database: _Database, expected: list[str]) -> None:
    with patch.object(DbState, 'db', staticmethod(lambda: database)):
        pending = DbState.pending_install_work()

    assert len(pending) == len(expected), pending
    for item, start in zip(pending, expected, strict=True):
        assert item.startswith(start), item


_HOLDERS = 'hivemind_haf_fyp_block_processing (pid=1152), hivesense_sync (pid=4176)'


@pytest.mark.parametrize('upgrade_schema', [False, True])
def test_locked_out_install_with_pending_work_fails_naming_the_holders(
    upgrade_schema: bool, caplog: pytest.LogCaptureFixture
) -> None:
    code, mocks = _enter_locked_out_install(_Database(recorded=_STALE, lock_holders=_HOLDERS), upgrade_schema)

    assert code == 1
    errors = [r.getMessage() for r in caplog.records if r.levelno == logging.ERROR]
    assert len(errors) == 1 and _HOLDERS in errors[0] and "table schema is behind" in errors[0], errors
    for mock in mocks.values():
        mock.assert_not_called()


@pytest.mark.parametrize('upgrade_schema', [False, True])
def test_locked_out_install_with_nothing_pending_succeeds(upgrade_schema: bool) -> None:
    code, mocks = _enter_locked_out_install(
        _Database(recorded=table_schema_digest(), lock_holders=_HOLDERS), upgrade_schema
    )

    assert code == 0
    for mock in mocks.values():
        mock.assert_not_called()


def _enter_locked_out_install(database: _Database, upgrade_schema: bool) -> tuple[Any, dict[str, MagicMock]]:
    """Enter an installer SyncHiveDb whose try_acquire_app_install_lock returns false; return its exit code."""
    connection = MagicMock()
    connection.query_one.return_value = False
    conf = MagicMock()
    conf.db.return_value = connection
    with _installer(database) as mocks, patch('hive.indexer.sync.set_custom_signal_handlers'):
        sync = SyncHiveDb(conf=conf, enter_sync=False, upgrade_schema=upgrade_schema)
        try:
            with pytest.raises(SystemExit) as exited, sync:
                raise AssertionError('the install entered despite the lock')
        finally:
            sync._massive_consume_blocks_thread_pool.shutdown()
    assert "try_acquire_app_install_lock('hivemind')" in connection.query_one.call_args.args[0]
    return exited.value.code, mocks


def test_sync_entry_exits_non_zero_on_a_behind_schema(caplog: pytest.LogCaptureFixture) -> None:
    connection = MagicMock()
    conf = MagicMock()
    conf.db.return_value = connection
    with (
        _installer(_Database(recorded=_STALE)),
        patch('hive.indexer.sync.set_custom_signal_handlers'),
        patch.object(DbState, 'vacuum_workers', DbState.vacuum_workers),
        patch.object(Community, 'start_block', Community.start_block),
        pytest.raises(SystemExit) as exited,
    ):
        sync = SyncHiveDb(conf=conf, enter_sync=True, upgrade_schema=False)
        try:
            with sync:
                raise AssertionError('sync entered on a behind schema')
        finally:
            sync._massive_consume_blocks_thread_pool.shutdown()

    assert exited.value.code == 1
    errors = [r.getMessage() for r in caplog.records if r.levelno == logging.ERROR]
    assert len(errors) == 1 and errors[0].startswith('Refusing to sync:') and 'upgrade_schema' in errors[0]


def test_fk_drop_refuses_a_missing_table_before_dropping_anything() -> None:
    database = _Database(missing_tables=('hive_moderation_log',))
    with (
        patch.object(DbState, 'db', staticmethod(lambda: database)),
        patch.multiple(DbState, _fk_were_disabled=False),
        pytest.raises(TableSchemaBehindError, match=r'no hivemind_app\.hive_moderation_log; .*upgrade_schema'),
    ):
        DbState.ensure_fk_are_disabled()

    assert not [sql for sql in database.statements if 'drop' in sql.lower()]


def test_index_restore_refuses_a_missing_table_before_restoring_anything() -> None:
    database = _Database(missing_tables=('hive_moderation_log',))
    process = MagicMock()
    with (
        patch.object(DbState, 'db', staticmethod(lambda: database)),
        patch.object(DbState, 'process_tasks_in_threads', process),
        pytest.raises(TableSchemaBehindError, match=r'no hivemind_app\.hive_moderation_log'),
    ):
        DbState._restore_indexes_in_threads()

    process.assert_not_called()
