"""Guard the #343 connection-tracking contract at the massive->live handoff.

pg_stat_activity is cached per transaction, and live mode keeps the
app_next_iteration transaction open across the handoff (#336), so every read
must first drop the cached snapshot -- and the post-block check must flag only
connections that were *opened* during the block, never ones that departed.
"""

from unittest.mock import MagicMock, call, patch

import pytest

from hive.indexer.sync import SyncHiveDb


def _sync_with_db(db):
    sync = SyncHiveDb.__new__(SyncHiveDb)
    sync._db = db
    return sync


def _sql_calls(db):
    """All SQL strings executed on the mock, in order, whichever query_* method was used."""
    return [c.args[0] for c in db.mock_calls if c.args and isinstance(c.args[0], str)]


def test_departed_connections_are_not_a_leak():
    SyncHiveDb._assert_connections_closed(['hivemind_A', 'hivemind_root'], ['hivemind_root'])


def test_full_disconnect_at_shutdown_is_not_a_leak():
    SyncHiveDb._assert_connections_closed(['hivemind_A', 'hivemind_B', 'hivemind_root'], [])


def test_new_connection_is_reported_as_leak():
    with pytest.raises(AssertionError) as excinfo:
        SyncHiveDb._assert_connections_closed(['hivemind_root'], ['hivemind_root', 'hivemind_X'])
    assert "leaked: ['hivemind_X']" in str(excinfo.value)


def test_active_connections_read_clears_snapshot_first():
    db = MagicMock()
    db.query_col.return_value = ['hivemind_root']

    assert _sync_with_db(db)._get_active_db_connections() == ['hivemind_root']

    sql = _sql_calls(db)
    assert len(sql) == 2
    assert sql[0] == "SELECT pg_stat_clear_snapshot()"
    assert 'pg_stat_activity' in sql[1]
    assert 'pid' not in sql[1]


def test_terminate_stale_connections_polls_with_fresh_snapshots():
    db = MagicMock()
    db.query_one.return_value = 4242
    db.query_all.return_value = [(True, 'hivemind_Z')]
    db.query_col.side_effect = [['hivemind_Z'], []]

    with patch('hive.indexer.sync.time.sleep') as sleep:
        _sync_with_db(db)._terminate_stale_connections()

    assert sleep.call_count == 2  # one per poll; loop exited as soon as the list was empty
    sql = _sql_calls(db)
    clear = "SELECT pg_stat_clear_snapshot()"
    # A clear precedes the terminate select and each of the two polls.
    assert sql.count(clear) == 3
    for i, stmt in enumerate(sql):
        if 'pg_stat_activity' in stmt:
            assert sql[i - 1] == clear, f"pg_stat_activity read at {i} not preceded by a snapshot clear"
    polls = [c for c in db.query_col.call_args_list]
    assert (
        polls
        == [
            call(
                "SELECT application_name FROM pg_stat_activity WHERE application_name LIKE 'hivemind_%' AND pid != 4242"
            )
        ]
        * 2
    )


def test_terminate_stale_connections_skips_wait_when_nothing_terminated():
    db = MagicMock()
    db.query_one.return_value = 1
    db.query_all.return_value = []

    with patch('hive.indexer.sync.time.sleep') as sleep:
        _sync_with_db(db)._terminate_stale_connections()

    sleep.assert_not_called()
    db.query_col.assert_not_called()
