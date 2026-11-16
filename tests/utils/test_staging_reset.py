"""The TRUNCATE of the staging tables between batches: after ten calls or 10,000 blocks, whichever comes first."""

from unittest.mock import MagicMock

import pytest

from hive.indexer.blocks import Blocks


@pytest.fixture(autouse=True)
def _fresh_counters(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(Blocks, '_calls_since_staging_reset', 0)
    monkeypatch.setattr(Blocks, '_blocks_since_staging_reset', 0)


def _resets(blocks_per_call: int, calls: int) -> list[int]:
    """The 1-based calls after which the staging tables were truncated."""
    db = MagicMock()
    resets: list[int] = []
    for call in range(1, calls + 1):
        Blocks._reset_staging_tables_if_due(db, blocks_per_call)
        if db.query_no_return.call_count > len(resets):
            resets.append(call)
    for args in db.query_no_return.call_args_list:
        assert args.args == ('SELECT hivemind_app.reset_staging_tables()',)
    return resets


@pytest.mark.parametrize(
    ('blocks_per_call', 'expected'),
    [
        (1, [10, 20]),  # live sync: one block per call
        (1000, [10, 20]),  # 1000-block massive batches
        (2500, [4, 8, 12, 16, 20]),
        (10000, list(range(1, 21))),
        (100000, list(range(1, 21))),
    ],
)
def test_staging_reset_bounds_calls_and_blocks(blocks_per_call: int, expected: list[int]) -> None:
    assert _resets(blocks_per_call, 20) == expected
