"""Tests for the order in which mock block files are loaded into a shared block."""

import json
from collections.abc import Iterator
from pathlib import Path

import pytest

from hive.indexer.mocking.mock_block_provider import MockBlockProvider


def _write_block(path: Path, block_num: int, marker: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({str(block_num): {'transactions': [{'operations': [marker]}]}}))


def test_shared_block_takes_ops_in_file_path_order_whatever_the_directory_order(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _write_block(tmp_path / 'community_op' / 'mock_block_data_community.json', 4998001, 'community')
    _write_block(tmp_path / 'follow_op' / 'mock_block_data_follow.json', 4998001, 'follow')
    _write_block(tmp_path / 'reblog_op' / 'mock_block_data_reblog.json', 4998001, 'reblog')

    listed = Path.rglob

    def reverse_listing(self: Path, pattern: str) -> Iterator[Path]:
        return iter(sorted(listed(self, pattern), reverse=True))

    monkeypatch.setattr(Path, 'rglob', reverse_listing)
    monkeypatch.setattr(MockBlockProvider, 'block_data', {})
    monkeypatch.setattr(MockBlockProvider, 'max_block', 0)

    MockBlockProvider.load_block_data(str(tmp_path))

    transactions = MockBlockProvider.block_data[4998001]['transactions']
    assert [tx['operations'][0] for tx in transactions] == ['community', 'follow', 'reblog']
