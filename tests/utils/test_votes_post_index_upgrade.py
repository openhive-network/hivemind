"""Guard the online replacement of hive_votes' post index by `hive upgrade_schema`.

perform_db_upgrade builds hive_votes_post_id_voter_id_covering_idx with CREATE INDEX
CONCURRENTLY, which refuses to run in a transaction block, so every statement goes on
its own; it registers the index after building it and drops the old one last, and first
drops an INVALID index an interrupted build left.
"""

from typing import Any
from unittest.mock import MagicMock, patch

from hive.db.schema import perform_db_upgrade

_NEW = 'hive_votes_post_id_voter_id_covering_idx'
_OLD = 'hive_votes_post_id_voter_id_idx'


class _Owner:
    """The schema owner's connection; `invalid_left` says whether an earlier build left the new index INVALID."""

    def __init__(self, invalid_left: bool) -> None:
        self.invalid_left = invalid_left
        self.statements: list[str] = []

    def query_one(self, sql: str, **kwargs: Any) -> Any:
        if 'indisvalid' in sql and _NEW in sql:
            return True if self.invalid_left else None
        return None

    def query_no_return(self, sql: str, **kwargs: Any) -> None:
        self.statements.append(sql)


def _upgrade(invalid_left: bool) -> list[str]:
    owner = _Owner(invalid_left)
    admin = MagicMock()
    admin.query_one.return_value = False
    with patch('hive.db.schema.execute_sql_script'):
        perform_db_upgrade(db=owner, admin_db=admin)
    return [s for s in owner.statements if _NEW in s or _OLD in s]


def test_builds_concurrently_registers_then_drops_the_old_index() -> None:
    statements = _upgrade(invalid_left=False)

    assert statements == [
        f'CREATE INDEX CONCURRENTLY IF NOT EXISTS {_NEW} ON hivemind_app.hive_votes (post_id, voter_id) INCLUDE (rshares, vote_percent)',
        f"SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS {_NEW} ON hivemind_app.hive_votes (post_id, voter_id) INCLUDE (rshares, vote_percent)')",
        f'DROP INDEX CONCURRENTLY IF EXISTS hivemind_app.{_OLD}',
    ]
    assert all(';' not in s for s in statements)


def test_an_invalid_index_left_by_an_interrupted_build_is_dropped_before_the_build() -> None:
    statements = _upgrade(invalid_left=True)

    assert statements[0] == f'DROP INDEX CONCURRENTLY IF EXISTS hivemind_app.{_NEW}'
    assert statements[1].startswith(f'CREATE INDEX CONCURRENTLY IF NOT EXISTS {_NEW} ')
    assert statements[-1] == f'DROP INDEX CONCURRENTLY IF EXISTS hivemind_app.{_OLD}'
