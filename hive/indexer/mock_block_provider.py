""" Data provider for test operations """
import logging
from hive.indexer.mock_data_provider import MockDataProvider

log = logging.getLogger(__name__)

class MockBlockProvider(MockDataProvider):
    """ Data provider for test ops """
    @classmethod
    def add_block_data(cls, block_num, transactions):
        if block_num in cls.block_data:
            cls.block_data[str(block_num)].extend(transactions)
        else:
            cls.block_data[str(block_num)] = transactions

    @classmethod
    def get_block_data(cls, block_num, pop=False):
        if pop:
            return cls.block_data.pop(str(block_num), None)
        return cls.block_data.get(str(block_num), None)

    @classmethod
    def get_max_block_number(cls):
        block_numbers = [int(block) for block in cls.block_data]
        block_numbers.append(0)
        return max(block_numbers)

    @classmethod
    def get_blocks_greater_than(cls, block_num):
        return sorted([int(block) for block in cls.block_data if int(block) >= block_num])
