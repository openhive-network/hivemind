""" Data provider for test operations """
import logging
log = logging.getLogger(__name__)

from json import load

class MockDataProvider():
    """ Data provider for test operations """
    block_data = {}

    @classmethod
    def get_max_block_number(cls):
        block_numbers = [int(block) for block in cls.block_data]
        block_numbers.append(0)
        return max(block_numbers)

    @classmethod
    def load_block_data(cls, data_path):
        with open(data_path, "r") as data_file:
            cls.block_data = load(data_file)

    @classmethod
    def add_block_data(cls, block_num, transactions):
        if block_num in cls.block_data:
            cls.block_data[block_num].extend(transactions)
        else:
            cls.block_data[block_num] = transactions

    @classmethod
    def get_block_data(cls, block_num, pop=False):
        if pop:
            return cls.block_data.pop(block_num, None)
        return cls.block_data.get(block_num, None)
