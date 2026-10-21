"""Guard the initial-sync gate of massive sync.

A freshly installed database (hive_state as insert_seed_data leaves it) must
take the initial-sync path: drop the BM25 index so it is built once, in
finalization, over the finished hive_post_data, and convert tables to UNLOGGED.
A database some finalization has completed must keep both.
"""

from unittest.mock import MagicMock, patch

import pytest

from hive.db.db_state import DbState
from hive.db.schema import SEED_LAST_COMPLETED_BLOCK

BM25_DROP = "DROP INDEX IF EXISTS hivemind_app.hive_post_data_bm25_idx"


def _disable_indexes(last_completed_block_num: int | None) -> tuple[list[str], MagicMock]:
    """Run ensure_indexes_are_disabled on a database at the given last_completed_block_num."""
    statements: list[str] = []
    db = MagicMock()
    db.query_one.return_value = last_completed_block_num
    db.query_no_return.side_effect = statements.append
    set_logged = MagicMock()
    with (
        patch.multiple(DbState, _initial_sync=None, _indexes_were_disabled=False, _indexes_were_enabled=True),
        patch.object(DbState, 'db', staticmethod(lambda: db)),
        patch.object(DbState, '_drop_indexes_in_threads', staticmethod(lambda: None)),
        patch('hive.db.schema.set_logged_table_attribute', set_logged),
    ):
        DbState.ensure_indexes_are_disabled()
    return statements, set_logged


@pytest.mark.parametrize('last_completed', [None, 0, SEED_LAST_COMPLETED_BLOCK])
def test_fresh_database_drops_bm25_and_goes_unlogged(last_completed: int | None) -> None:
    statements, set_logged = _disable_indexes(last_completed)
    assert BM25_DROP in statements
    assert set_logged.call_count == 1
    assert set_logged.call_args.args[1] is False


@pytest.mark.parametrize('last_completed', [SEED_LAST_COMPLETED_BLOCK + 1, 5000024])
def test_synced_database_keeps_bm25_and_logging(last_completed: int) -> None:
    statements, set_logged = _disable_indexes(last_completed)
    assert BM25_DROP not in statements
    set_logged.assert_not_called()
