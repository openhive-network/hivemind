"""Guard the handling of tables an older hivemind left UNLOGGED mid-sync.

Massive sync keeps its tables LOGGED. A database an older version left mid-sync
still has UNLOGGED ones: restoring indexes must SET LOGGED exactly those (the
tables FKs point to before the tables with the FKs), and a sync that started
LOGGED must pay nothing. The crash-truncation reset applies only while some
table is UNLOGGED.
"""

from unittest.mock import MagicMock, patch

import pytest

from hive.db.db_state import DbState
from hive.db.schema import ensure_tables_logged
from hive.indexer.sync import SyncHiveDb


def _db(unlogged: list[str]) -> tuple[MagicMock, list[str]]:
    """A database whose pg_class reports `unlogged` as relpersistence 'u'; also the SQL its clones ran."""
    converted: list[str] = []
    db = MagicMock()
    db.query_col.return_value = unlogged
    db.clone.return_value.query_no_return.side_effect = converted.append
    return db, converted


def test_logged_database_is_not_rewritten() -> None:
    db, converted = _db([])
    ensure_tables_logged(db)
    assert "relpersistence = 'u'" in db.query_col.call_args.args[0]
    assert converted == []
    db.clone.assert_not_called()


def test_only_unlogged_tables_are_set_logged_referenced_ones_first() -> None:
    db, converted = _db(['hive_mentions', 'hive_posts', 'hive_votes'])
    ensure_tables_logged(db)
    assert sorted(converted) == sorted(
        f'ALTER TABLE hivemind_app.{t} SET LOGGED' for t in ('hive_mentions', 'hive_posts', 'hive_votes')
    )
    assert converted[-1] == 'ALTER TABLE hivemind_app.hive_mentions SET LOGGED'


def test_index_restore_sets_legacy_unlogged_tables_logged() -> None:
    db, converted = _db(['hive_votes'])
    with (
        patch.multiple(DbState, _indexes_were_enabled=False, _indexes_were_disabled=True, _deferred_index_tables=[]),
        patch.object(DbState, 'db', staticmethod(lambda: db)),
        patch.object(DbState, '_restore_indexes_in_threads', staticmethod(lambda **kwargs: None)),
    ):
        DbState.ensure_indexes_are_enabled()
    assert converted == ['ALTER TABLE hivemind_app.hive_votes SET LOGGED']


def _check_consistency(unlogged: list[str]) -> list[str]:
    """Run the crash-truncation check on a database whose seed account is gone; return its SQL."""
    statements: list[str] = []
    db = MagicMock()
    db.query_col.return_value = unlogged
    db.query_one.return_value = False
    db.query_no_return.side_effect = statements.append
    sync = SyncHiveDb.__new__(SyncHiveDb)
    sync._db = db
    with (
        patch('hive.indexer.sync.Blocks.last_imported', return_value=4999990),
        patch('hive.indexer.sync.Blocks.last_completed', return_value=0),
        patch('hive.indexer.hive_db.haf_functions.prepare_app_context'),
        patch('hive.db.schema.insert_seed_data'),
    ):
        sync._check_unlogged_data_consistency()
    return statements


@pytest.mark.parametrize(('unlogged', 'reset'), [([], False), (['hive_accounts'], True)])
def test_truncation_reset_only_while_tables_are_unlogged(unlogged: list[str], reset: bool) -> None:
    statements = _check_consistency(unlogged)
    assert any(sql.startswith('TRUNCATE hivemind_app.hive_accounts') for sql in statements) is reset
