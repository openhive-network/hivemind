""" Data provider for test operations """
import logging
import os
from hive.indexer.mock_data_provider import MockDataProvider

log = logging.getLogger(__name__)

class MockBlockProvider(MockDataProvider):

    max_block = 0

    """ Data provider for test ops """
    @classmethod
    def load_block_data(cls, data_path):
        cls.max_block = 0

        if os.path.isdir(data_path):
            log.warning("Loading mock block data from directory: {}".format(data_path))
            cls.add_block_data_from_directory(data_path)
        else:
            log.warning("Loading mock block data from file: {}".format(data_path))
            cls.add_block_data_from_file(data_path)

    @classmethod
    def add_block_data_from_directory(cls, dir_name):
        for name in os.listdir(dir_name):
            file_path = os.path.join(dir_name, name)
            if os.path.isfile(file_path) and file_path.endswith(".json"):
                cls.add_block_data_from_file(file_path)

    @classmethod
    def add_block_data_from_file(cls, file_name):
        from json import load
        data = {}
        with open(file_name, "r") as src:
            data = load(src)
        for block_num, transactions in data.items():
            cls.add_block_data(block_num, transactions)

    @classmethod
    def add_block_data(cls, _block_num, transactions):
        block_num = int(_block_num)

        if block_num > cls.max_block:
            cls.max_block = block_num

        if block_num in cls.block_data:
            cls.block_data[block_num].extend(transactions)
        else:
            cls.block_data[block_num] = transactions

    @classmethod
    def get_block_data(cls, block_num):
        return cls.block_data.get(block_num, None)

    @classmethod
    def get_max_block_number(cls):
        return cls.max_block

