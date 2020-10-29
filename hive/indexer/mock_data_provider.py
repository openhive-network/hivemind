""" Data provider for test operations """
import logging
log = logging.getLogger(__name__)

from json import load

class MockDataProvider():
    """ Data provider for test operations """
    block_data = {}

    @classmethod
    def load_block_data(cls, data_path):
        with open(data_path, "r") as data_file:
            cls.block_data = load(data_file)
