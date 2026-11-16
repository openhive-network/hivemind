"""PostDataCache.flush hands mention processing each post's body at the end of every block it had an op in."""

from collections.abc import Iterator
from typing import Any
from unittest.mock import MagicMock

import pytest

from hive.indexer.db_adapter_holder import DbLiveContextHolder
from hive.indexer.post_data_cache import PostDataCache

_MARKER = 'UPDATE hivemind_app._batch_queue SET post_data_applied = TRUE'


@pytest.fixture
def db(monkeypatch: pytest.MonkeyPatch) -> Iterator[MagicMock]:
    db = MagicMock()
    db.query_all.return_value = [MagicMock(_mapping={'body': 'stored body @carol'})]
    monkeypatch.setattr(PostDataCache, 'db', db)
    monkeypatch.setattr(DbLiveContextHolder, '_live_context', False)
    yield db
    PostDataCache._data.clear()
    PostDataCache._blocks.clear()
    PostDataCache._block_bodies.clear()


def _post(body: str | None) -> dict[str, Any]:
    return {'title': None, 'body': body, 'json': None, 'is_root': 'true'}


def _mention_call(db: MagicMock, mentions_after_block: int = 0) -> tuple[tuple[Any, ...], ...] | None:
    """Flush; return the snapshot arrays handed to process_hive_post_mentions, None when it is not called."""
    statements: list[tuple[str, tuple[Any, ...]]] = []
    db.query_all_raw.side_effect = lambda sql, params=(): statements.append((sql, params))
    db.query_no_return.reset_mock()
    PostDataCache.flush(mentions_after_block=mentions_after_block)

    write, *mentions = statements
    assert 'INSERT INTO hivemind_app.hive_post_data' in write[0]
    assert 'process_hive_post_mentions' not in write[0]
    db.query_no_return.assert_called_once_with(_MARKER)
    if not mentions:
        return None
    ((sql, params),) = mentions
    assert sql == 'SELECT hivemind_app.process_hive_post_mentions(%s::INT[], %s::INT[], %s::TEXT[])'
    return tuple(zip(*params, strict=True))


def test_each_block_of_a_post_is_one_snapshot_and_the_last_reads_the_flushed_body(db: MagicMock) -> None:
    PostDataCache.add_data(1, _post('created @alice'), True, 100)
    PostDataCache.add_data(1, _post('edited @bob'), False, 100)
    PostDataCache.add_data(1, _post('edited again @bob'), False, 105)
    PostDataCache.add_data(1, _post('last @dave'), False, 107)
    PostDataCache.add_data(2, _post('other @erin'), True, 105)

    assert _mention_call(db) == (
        (1, 100, 'edited @bob'),
        (1, 105, 'edited again @bob'),
        (1, 107, None),
        (2, 105, None),
    )


def test_a_block_whose_ops_set_no_body_yet_takes_the_stored_body(db: MagicMock) -> None:
    PostDataCache.add_data(3, _post(None), False, 200)
    PostDataCache.add_data(3, _post('new body'), False, 201)

    assert _mention_call(db) == ((3, 200, 'stored body @carol'), (3, 201, None))


def test_blocks_outside_the_notification_window_process_no_mentions(db: MagicMock) -> None:
    PostDataCache.add_data(4, _post('old @alice'), True, 300)
    PostDataCache.add_data(4, _post('newer @bob'), False, 301)
    PostDataCache.add_data(5, _post('old @carol'), True, 299)

    assert _mention_call(db, mentions_after_block=300) == ((4, 301, None),)

    PostDataCache.add_data(6, _post('old @dave'), True, 300)
    assert _mention_call(db, mentions_after_block=300) is None


def test_flush_forgets_the_snapshots(db: MagicMock) -> None:
    PostDataCache.add_data(7, _post('a'), True, 400)
    PostDataCache.add_data(7, _post('b'), False, 401)
    _mention_call(db)

    PostDataCache.add_data(7, _post('c'), False, 402)
    assert _mention_call(db) == ((7, 402, None),)
