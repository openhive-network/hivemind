"""Guard the SQL hivemind runs when sync starts.

Hivemind's custom_json filters are all bounded by a block range and served
by the block-number indexes, so it must not ask HAF for a custom_json type
index on hafd.operations: building one is a blocking CREATE INDEX that stalls
every HAF application (haf#387).
"""

from collections.abc import Callable
from typing import Any
from unittest.mock import MagicMock, patch

from hive.indexer.sync import SyncHiveDb


def _sync_start_statements() -> list[str]:
    """Run SyncHiveDb.run up to its main loop on a clean restart; return the SQL it sent."""
    statements: list[str] = []
    db = MagicMock()

    def record(result: Any) -> Callable[..., Any]:
        def query(sql: str, *args: Any, **kwargs: Any) -> Any:
            statements.append(sql)
            return result

        return query

    db.query_no_return.side_effect = record(None)
    db.query_one.side_effect = record(1234)
    db.query_all.side_effect = record([])
    db.query_row.side_effect = record(None)

    sync = SyncHiveDb.__new__(SyncHiveDb)
    sync._db = db
    sync._conf = MagicMock()

    with (
        patch('hive.indexer.sync.Blocks.set_head_date'),
        patch('hive.indexer.sync.Blocks.last_imported', return_value=4999990),
        patch('hive.indexer.sync.Blocks.last_completed', return_value=4999990),
        patch.object(SyncHiveDb, '_get_active_db_connections', return_value=[]),
        patch.object(SyncHiveDb, '_main_loop') as main_loop,
    ):
        sync.run()
    main_loop.assert_called_once()
    return statements


def test_sync_start_requests_no_custom_json_type_index() -> None:
    statements = _sync_start_statements()

    assert statements, 'sync start ran no SQL; the recording mock is not wired in'
    for sql in statements:
        assert 'create_custom_json_type_index' not in sql, sql
        assert 'register_custom_json_type_index' not in sql, sql
