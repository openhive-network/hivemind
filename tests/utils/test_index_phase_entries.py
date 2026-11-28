"""Guard the index phase each way out of MASSIVE_WITHOUT_INDEXES enters it with.

A sync leaves MASSIVE_WITHOUT_INDEXES for MASSIVE_WITH_INDEXES (a production
node, whose HAF lags the chain head), for live, or at --test-max-block. Each
restores the indexes with hive_posts' deferred to finalization's recompute and
the BM25 index built beside the hive_votes ordering, so no entry leaves the BM25
build to run after the recompute.
"""

from collections.abc import Iterator
from contextlib import contextmanager
from unittest.mock import MagicMock, patch

import pytest

from hive.db.db_state import DbState
from hive.indexer.sync import SyncHiveDb

_INDEX_PHASE = {'defer_to_finalization': True, 'build_search_index': True}
_DBSTATE = (
    'set_massive_sync',
    'ensure_off_synchronous_commit',
    'ensure_on_synchronous_commit',
    'ensure_fk_are_disabled',
    'are_indexes_enabled',
    'ensure_indexes_are_enabled',
    'restore_wal_safety_after_massive_sync',
    'close_admin_db',
    'ensure_finalize_massive_sync',
    'ensure_fk_are_enabled',
    'start_visibility_watch',
)


def _sync(stage: str) -> SyncHiveDb:
    db = MagicMock()
    db.is_trx_active.return_value = False

    def query_one(sql: str) -> str | bool:
        if 'get_current_stage_name' in sql:
            return stage
        if 'is_instance_ready' in sql:
            return True
        raise AssertionError(f'unexpected query: {sql}')

    db.query_one.side_effect = query_one

    sync = SyncHiveDb.__new__(SyncHiveDb)
    sync._db = db
    sync._live_prepared = False
    sync._massive_consume_blocks_futures = None
    sync._ops_prefetch = None
    sync._last_block_to_process = None
    return sync


@contextmanager
def _dbstate() -> Iterator[MagicMock]:
    """DbState with the index restore recorded and its other steps doing nothing; yield the restore's mock."""
    mocks = {name: MagicMock(return_value=False) for name in _DBSTATE}
    with (
        patch.multiple(DbState, **mocks),
        patch('hive.indexer.sync.Blocks.last_imported', return_value=4999990),
        patch('hive.indexer.sync.Blocks.last_completed', return_value=4999000),
        patch('hive.indexer.sync.Blocks.set_stage_b_handoff'),
        patch('hive.indexer.sync.Blocks.wait_for_stage_b'),
        patch.object(SyncHiveDb, '_process_massive_blocks') as process_massive_blocks,
        patch.object(SyncHiveDb, '_process_live_blocks') as process_live_blocks,
    ):
        yield mocks['ensure_indexes_are_enabled']
    process_live_blocks.assert_not_called()
    if process_massive_blocks.called:
        process_massive_blocks.assert_called_once_with(4999991, 5000990, 'MASSIVE_WITH_INDEXES')


def _run_one_iteration(stage: str) -> None:
    sync = _sync(stage)
    with (
        patch.object(SyncHiveDb, '_query_for_app_next_block', return_value=(4999991, 5000990)),
        patch.object(SyncHiveDb, '_break_requested', side_effect=[False, True]),
    ):
        sync._main_loop(lambda stage: False, active_connections_before=[])


@pytest.mark.parametrize('stage', ['MASSIVE_WITH_INDEXES', 'live'])
def test_the_stage_after_massive_without_indexes_builds_bm25_in_the_index_phase(stage: str) -> None:
    with _dbstate() as restore:
        _run_one_iteration(stage)

    restore.assert_called_once_with(**_INDEX_PHASE)


def test_reaching_test_max_block_builds_bm25_in_the_index_phase() -> None:
    sync = _sync('MASSIVE_WITHOUT_INDEXES')
    sync._last_block_to_process = 4999990
    with (
        _dbstate() as restore,
        patch('hive.indexer.sync.can_continue_thread', return_value=True),
        patch.object(SyncHiveDb, '_on_stop_synchronization'),
    ):
        assert sync._break_requested(4999990, active_connections_before=[])

    restore.assert_called_once_with(**_INDEX_PHASE)


def test_massive_with_indexes_entered_with_indexes_enabled_restores_nothing() -> None:
    with _dbstate() as restore, patch.object(DbState, 'are_indexes_enabled', return_value=True):
        _run_one_iteration('MASSIVE_WITH_INDEXES')

    restore.assert_not_called()
