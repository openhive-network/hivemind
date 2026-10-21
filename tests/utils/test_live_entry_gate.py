"""Guard the gate in front of hivemind's massive->live finalization.

With early block processing (haf#379) HAF hands blocks to hivemind while hived
restores the indexes of its massive sync, and hived already reports LIVE then,
so hive.app_next_iteration can put hivemind into the `live` stage while
hive.is_instance_ready() is false. Hivemind must not finalize (indexes, FKs,
VACUUM, feed cache, ...) until HAF is ready, and must not keep the advanced
context position of the iteration it skipped.
"""

from unittest.mock import MagicMock, patch

from hive.db.db_state import DbState
from hive.indexer.sync import SyncHiveDb

_DBSTATE_LIVE_ENTRY = (
    'set_massive_sync',
    'ensure_on_synchronous_commit',
    'ensure_indexes_are_enabled',
    'restore_wal_safety_after_massive_sync',
    'close_admin_db',
    'ensure_finalize_massive_sync',
    'ensure_fk_are_enabled',
)


def _run_live_iteration(instance_ready: bool) -> tuple[dict[str, MagicMock], list[str]]:
    """Run _main_loop for one `live` iteration, then stop it; return the DbState mocks and the SQL run."""
    statements: list[str] = []
    db = MagicMock()
    db.is_trx_active.return_value = False
    db.query_no_return.side_effect = statements.append

    def query_one(sql: str) -> str | bool:
        statements.append(sql)
        if 'get_current_stage_name' in sql:
            return 'live'
        if 'is_instance_ready' in sql:
            return instance_ready
        raise AssertionError(f'unexpected query: {sql}')

    db.query_one.side_effect = query_one

    sync = SyncHiveDb.__new__(SyncHiveDb)
    sync._db = db
    sync._live_prepared = False
    sync._massive_consume_blocks_futures = None

    dbstate = {name: MagicMock(return_value=False) for name in _DBSTATE_LIVE_ENTRY}
    with (
        patch.multiple(DbState, **dbstate),
        patch('hive.indexer.sync.Blocks.last_imported', return_value=4999990),
        patch('hive.indexer.sync.Blocks.last_completed', return_value=4999000),
        patch.object(SyncHiveDb, '_query_for_app_next_block', return_value=(4999991, 4999991)),
        patch.object(SyncHiveDb, '_break_requested', side_effect=[False, True]),
        patch.object(SyncHiveDb, '_process_live_blocks') as process_live_blocks,
        patch('hive.indexer.sync.time.sleep') as sleep,
    ):
        sync._main_loop(lambda stage: True, active_connections_before=[])
    process_live_blocks.assert_not_called()
    assert sleep.called == (not instance_ready)
    return dbstate, statements


def test_live_stage_waits_while_haf_restores_indexes() -> None:
    dbstate, statements = _run_live_iteration(instance_ready=False)

    for name, mock in dbstate.items():
        assert not mock.called, f'DbState.{name} ran while HAF restores its indexes'
    # The context position app_next_iteration advanced is rolled back, not committed.
    assert 'ROLLBACK' in statements
    assert 'COMMIT' not in statements


def test_live_stage_finalizes_once_haf_is_ready() -> None:
    dbstate, statements = _run_live_iteration(instance_ready=True)

    dbstate['ensure_finalize_massive_sync'].assert_called_once_with(4999990, 4999000)
    dbstate['set_massive_sync'].assert_called_once_with(False)
    dbstate['ensure_fk_are_enabled'].assert_called_once_with()
    assert 'SELECT hive.is_instance_ready()' in statements
