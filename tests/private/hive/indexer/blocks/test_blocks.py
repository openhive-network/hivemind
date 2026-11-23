"""Private-interface tests for hive.indexer.blocks internals."""

import pytest

from hive.indexer.blocks import _parse_kill_point


@pytest.mark.parametrize(
    ('value', 'expected'),
    [(None, None), ('', None), ('flush_committed:4500001', ('flush_committed', 4500001))],
)
def test_the_kill_point_is_a_point_and_a_batch(value: str | None, expected: tuple[str, int] | None) -> None:
    assert _parse_kill_point(value) == expected


@pytest.mark.parametrize('value', ['flush_committed', 'nowhere:1', 'flush_committed:x', 'flush_committed:-1'])
def test_any_other_kill_point_is_refused(value: str) -> None:
    with pytest.raises(ValueError, match='POINT:BLOCK'):
        _parse_kill_point(value)
