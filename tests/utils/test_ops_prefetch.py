"""The prefetch of the next massive batch's operations: which range it loads, and when a batch may use it."""

import threading
from typing import Any
from unittest.mock import MagicMock

import psycopg2
import pytest

from hive.indexer.ops_prefetch import OpsPrefetch
from hive.indexer.sync import SyncHiveDb

_PREFETCH = 'SELECT hivemind_app.prefetch_ops_staging('


def _db(loaded_last: int | None, statements: list[str], release: threading.Event | None = None) -> MagicMock:
    """A connection whose prefetch_ops_staging returns `loaded_last`, after `release` is set when given."""
    db = MagicMock()
    db.query_no_return.side_effect = statements.append

    def query_one(sql: str) -> Any:
        statements.append(sql)
        if release is not None:
            assert release.wait(5)
        return loaded_last

    db.query_one.side_effect = query_one
    return db


def test_a_batch_uses_the_prefetch_that_covers_it() -> None:
    statements: list[str] = []
    prefetch = OpsPrefetch(_db(2000, statements))

    prefetch.start(1001, 2000)

    assert prefetch.take(1001, 2000) is not None
    assert statements == ['START TRANSACTION', f'{_PREFETCH}1001, 2000)', 'COMMIT']
    prefetch.close()


def test_a_shorter_range_from_the_same_block_is_served_from_the_prefetch() -> None:
    prefetch = OpsPrefetch(_db(11000, []))
    prefetch.start(1001, 11000)

    assert prefetch.take(1001, 2000) is not None
    prefetch.close()


@pytest.mark.parametrize(
    ('loaded_last', 'batch'),
    [
        (None, (1001, 2000)),  # HAF had no consistent block of the range yet
        (1500, (1001, 2000)),  # it had only part of it
        (2000, (1002, 2000)),  # HAF handed out a range from another block
    ],
)
def test_a_batch_the_prefetch_does_not_cover_is_loaded_from_haf(
    loaded_last: int | None, batch: tuple[int, int]
) -> None:
    prefetch = OpsPrefetch(_db(loaded_last, []))
    prefetch.start(1001, 2000)

    assert prefetch.take(*batch) is None
    prefetch.close()


def test_take_waits_for_the_load_in_flight() -> None:
    release = threading.Event()
    prefetch = OpsPrefetch(_db(2000, [], release))
    prefetch.start(1001, 2000)
    taken: list[float | None] = []
    taker = threading.Thread(target=lambda: taken.append(prefetch.take(1001, 2000)))

    taker.start()
    taker.join(0.2)
    assert taker.is_alive()
    release.set()
    taker.join(5)

    assert taken and taken[0] is not None
    prefetch.close()


def test_without_a_prefetch_a_batch_is_loaded_from_haf() -> None:
    prefetch = OpsPrefetch(_db(2000, []))

    assert prefetch.take(1001, 2000) is None
    prefetch.close()


def test_a_second_prefetch_before_the_first_is_taken_is_refused() -> None:
    prefetch = OpsPrefetch(_db(2000, []))
    prefetch.start(1001, 2000)

    with pytest.raises(RuntimeError):
        prefetch.start(2001, 3000)
    prefetch.close()


def test_a_failed_prefetch_is_rolled_back_and_raised_to_the_batch() -> None:
    statements: list[str] = []
    db = _db(2000, statements)
    db.query_one.side_effect = psycopg2.OperationalError('server closed the connection')
    prefetch = OpsPrefetch(db)
    prefetch.start(1001, 2000)

    with pytest.raises(psycopg2.OperationalError):
        prefetch.take(1001, 2000)
    assert statements == ['START TRANSACTION', 'ROLLBACK']
    prefetch.close()


def test_close_discards_the_load_in_flight_and_closes_the_connection() -> None:
    db = _db(2000, [])
    db.query_one.side_effect = psycopg2.OperationalError('server closed the connection')
    prefetch = OpsPrefetch(db)
    prefetch.start(1001, 2000)

    prefetch.close()

    db.close.assert_called_once()


def _sync(max_batch: int | None = None, last_block_to_process: int | None = None) -> SyncHiveDb:
    sync = SyncHiveDb.__new__(SyncHiveDb)
    sync._max_batch = max_batch
    sync._massive_batch_blocks = 10_000
    sync._last_block_to_process = last_block_to_process
    return sync


@pytest.mark.parametrize(
    ('sync', 'stage', 'expected'),
    [
        (_sync(), 'MASSIVE_WITHOUT_INDEXES', (20_001, 30_000)),
        (_sync(), 'MASSIVE_WITH_INDEXES', (20_001, 21_000)),
        (_sync(max_batch=500), 'MASSIVE_WITHOUT_INDEXES', (20_001, 20_500)),
        (_sync(last_block_to_process=25_000), 'MASSIVE_WITHOUT_INDEXES', (20_001, 25_000)),
        (_sync(last_block_to_process=20_000), 'MASSIVE_WITHOUT_INDEXES', None),
    ],
)
def test_the_prefetched_range_is_the_one_haf_hands_out_next(
    sync: SyncHiveDb, stage: str, expected: tuple[int, int] | None
) -> None:
    assert sync._expected_next_range(20_000, stage) == expected
