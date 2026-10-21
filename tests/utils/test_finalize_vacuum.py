"""Guard the vacuums of initial-sync finalization.

Only hive_posts is rewritten with VACUUM FULL, once, after its last write;
no plain vacuum is followed by a second vacuum of the same table; and every
table's last vacuum of the sync freezes it.
"""

import re
from collections.abc import Callable, Sequence
from typing import Any
from unittest.mock import MagicMock, patch

from hive.db.db_state import DbState

TABLES = [
    'hivemind_app.hive_posts',
    'hivemind_app.hive_post_data',
    'hivemind_app.hive_votes',
    'hivemind_app.hive_permlink_data',
    'hivemind_app.hive_feed_cache',
    'hivemind_app.hive_notification_cache',
]


def _initial_finalization_vacuums() -> list[tuple[str, str]]:
    """Run the initial-sync path of ensure_finalize_massive_sync and return its VACUUM statements in order."""
    statements: list[str] = []
    db = MagicMock()
    db.query_all.return_value = [MagicMock(_mapping={'table_name': t}) for t in TABLES]
    db.clone.return_value.query_no_return_autocommit.side_effect = statements.append

    def run_vacuums_only(info: str, methods: Sequence[tuple[str, Callable[..., None], list[Any]]]) -> None:
        for description, method, args in methods:
            if description.startswith('VACUUM '):
                method(*args)

    DbState._rshares_recalculated = False
    with (
        patch.object(DbState, 'db', staticmethod(lambda: db)),
        patch.object(DbState, 'process_tasks_in_threads', staticmethod(run_vacuums_only)),
        patch.multiple(
            DbState,
            _finish_posts_rshares=staticmethod(lambda *a: None),
            _finish_reputation_notification_scores=staticmethod(lambda *a: None),
            _finalize_completion_marker=staticmethod(lambda *a: None),
        ),
        patch('hive.signals.can_continue_thread', lambda: True),
    ):
        assert DbState.ensure_finalize_massive_sync(10**8, 0) is True
    vacuums = []
    for statement in statements:
        match = re.fullmatch(r'VACUUM \(([A-Z, ]+)\) (\S+)', statement)
        assert match, statement
        vacuums.append((match[1], match[2]))
    return vacuums


def test_only_hive_posts_is_rewritten_once() -> None:
    vacuums = _initial_finalization_vacuums()
    assert [table for options, table in vacuums if 'FULL' in options] == ['hivemind_app.hive_posts']


def test_vacuums_of_each_table() -> None:
    vacuums = _initial_finalization_vacuums()
    by_table: dict[str, list[str]] = {}
    for options, table in vacuums:
        by_table.setdefault(table, []).append(options)

    # Not written by finalization: frozen once, before it.
    for table in ('hive_post_data', 'hive_votes', 'hive_permlink_data'):
        assert by_table[f'hivemind_app.{table}'] == ['FREEZE, VERBOSE, ANALYZE']
    # Written by finalization: plain before it, frozen after it.
    for table in ('hive_feed_cache', 'hive_notification_cache'):
        assert by_table[f'hivemind_app.{table}'] == ['VERBOSE, ANALYZE', 'FREEZE, VERBOSE, ANALYZE']
    # hive_posts is also vacuumed after the rshares recalculation, before Part 0,
    # and compacted after finalization, before its freeze.
    assert by_table['hivemind_app.hive_posts'] == [
        'VERBOSE, ANALYZE',
        'VERBOSE, ANALYZE',
        'FULL, VERBOSE, ANALYZE',
        'FREEZE, VERBOSE, ANALYZE',
    ]
