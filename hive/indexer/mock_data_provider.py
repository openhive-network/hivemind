""" Data provider for test operations """
import logging
from json import load, dumps
log = logging.getLogger(__name__)

class MockDataProvider():
    """ Data provider for test operations """
    block_data = {}

    @classmethod
    def print_data(cls):
        print(dumps(cls.block_data, indent=4, sort_keys=True))
