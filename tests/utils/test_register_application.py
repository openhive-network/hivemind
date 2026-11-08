"""Guard the name hivemind registers under in the HAF application registry.

HAF's lock helpers find an application's registry row by the name it locks as,
so hivemind registers under 'hivemind', and an install refuses a row of its
context left under another name ('hivemind_app') instead of keeping it.
The install against a real HAF is checked by .aidev/app_registry_check.sql.
"""

from typing import Any, cast

import pytest

from hive.db.adapter import Db
from hive.indexer.hive_db.haf_functions import register_application


class _Db:
    """Answers the registry probes; `other_name` is the row holding hivemind_app under another name."""

    def __init__(self, other_name: str | None) -> None:
        self._other_name = other_name
        self.statements: list[str] = []

    def query_no_return(self, sql: str) -> None:
        self.statements.append(sql)

    def query_one(self, sql: str) -> Any:
        self.statements.append(sql)
        if 'to_regprocedure' in sql:
            return True
        if 'hafd.applications' in sql:
            return self._other_name
        raise AssertionError(f'unexpected query: {sql}')


def _app_register_calls(db: _Db) -> list[str]:
    return [sql for sql in db.statements if sql.startswith('SELECT hive.app_register(')]


def test_registers_under_the_lock_name() -> None:
    db = _Db(other_name=None)

    register_application(cast(Db, db))

    assert _app_register_calls(db) == [
        "SELECT hive.app_register('hivemind', ARRAY['hivemind_app']::hive.contexts_group, NULL, "
        "'hivemind_app.completed_block_num');"
    ]


def test_refuses_the_context_registered_under_another_name() -> None:
    db = _Db(other_name='hivemind_app')

    with pytest.raises(RuntimeError) as refused:
        register_application(cast(Db, db))

    assert "registered in the HAF application registry as 'hivemind_app', not 'hivemind'" in str(refused.value)
    assert "SELECT hive.app_unregister('hivemind_app');" in str(refused.value)
    assert _app_register_calls(db) == []
