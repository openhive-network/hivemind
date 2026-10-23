"""Guard how sync start asks HAF for hivemind's custom_json type index.

hive.create_custom_json_type_index runs a plain CREATE INDEX on hafd.operations
inside hivemind's transaction, which blocks hived's block writes for the whole
build. Sync start must only register the index with HAF's indexes controller
(built CONCURRENTLY), and skip the request on a HAF that cannot register it.
"""

import logging
from unittest.mock import MagicMock, patch

import pytest

from hive.conf import SCHEMA_NAME
from hive.indexer.hive_db.haf_functions import HIVEMIND_CUSTOM_JSON_TYPES
from hive.indexer.sync import SyncHiveDb


class _StopAfterIndexRequest(Exception):
    pass


def _start_sync(register_available: bool) -> list[str]:
    """Run SyncHiveDb.run up to the step after the index request; return the SQL run."""
    statements: list[str] = []
    db = MagicMock()
    db.query_no_return.side_effect = statements.append

    def query_one(sql: str) -> bool:
        statements.append(sql)
        if "to_regprocedure('hive.register_custom_json_type_index(text, text[])')" in sql:
            return register_available
        raise AssertionError(f'unexpected query: {sql}')

    db.query_one.side_effect = query_one

    sync = SyncHiveDb.__new__(SyncHiveDb)
    sync._db = db
    with (
        patch('hive.indexer.sync.Blocks.set_head_date', side_effect=_StopAfterIndexRequest),
        pytest.raises(_StopAfterIndexRequest),
    ):
        sync.run()
    return statements


def test_sync_start_registers_the_index_and_never_creates_it() -> None:
    statements = _start_sync(register_available=True)

    types_array = "ARRAY[" + ",".join(f"'{t}'" for t in HIVEMIND_CUSTOM_JSON_TYPES) + "]::TEXT[]"
    assert HIVEMIND_CUSTOM_JSON_TYPES == ['follow', 'reblog', 'community', 'notify']
    assert statements[-1] == f"SELECT hive.register_custom_json_type_index('{SCHEMA_NAME}', {types_array});"
    assert not any('create_custom_json_type_index' in sql for sql in statements)


def test_sync_start_without_haf_registration_warns_and_continues(caplog: pytest.LogCaptureFixture) -> None:
    with caplog.at_level(logging.WARNING, logger='hive.indexer.hive_db.haf_functions'):
        statements = _start_sync(register_available=False)

    assert len(statements) == 1
    assert 'to_regprocedure' in statements[0]
    assert not any('custom_json_type_index(' in sql and 'to_regprocedure' not in sql for sql in statements)
    warnings = [r for r in caplog.records if r.levelno == logging.WARNING]
    assert len(warnings) == 1
    assert 'hive.register_custom_json_type_index' in warnings[0].getMessage()
