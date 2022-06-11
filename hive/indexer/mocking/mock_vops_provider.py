""" Data provider for test vops """
import json
import logging
from typing import Optional

from hive.indexer.mocking.mock_data_provider import MockDataProvider

log = logging.getLogger(__name__)


class MockVopsProvider(MockDataProvider):
    """Data provider for test vops"""

    block_data = {}

    @classmethod
    def add_block_data_from_file(cls, filename) -> None:
        with open(filename, encoding='utf-8') as file:
            data = json.load(file)

        for block_num, block_content in data.items():
            cls._add_block_data(int(block_num), dict(block_content))

    @classmethod
    def _add_block_data(cls, block_num: int, block_content: dict) -> None:
        assert 'virtual_operations' in block_content

        if block_num in cls.block_data:
            cls.block_data[block_num]['virtual_operations'].extend(block_content['virtual_operations'])
        else:
            cls.block_data[block_num] = block_content

    @classmethod
    def get_mock_block_data(cls, block_number: int) -> Optional[dict]:
        return cls.block_data.get(block_number, None)

    @classmethod
    def get_mock_vops(cls, block_number: int) -> Optional[dict]:
        mock_block_data = cls.get_mock_block_data(block_number)

        return mock_block_data.get('virtual_operations', None) if mock_block_data else None
