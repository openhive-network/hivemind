""" Data provider for test operations """
import logging
from hive.indexer.mock_data_provider import MockDataProvider

log = logging.getLogger(__name__)

class MockBlockProvider(MockDataProvider):
    """ Data provider for test ops """
    @classmethod
    def get_blocks_greater_than(cls, block_num):
        return [int(block) for block in cls.block_data if int(block) >= block_num]
