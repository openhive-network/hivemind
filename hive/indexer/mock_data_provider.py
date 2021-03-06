""" Data provider for test operations """
import os
import logging

from json import dumps

log = logging.getLogger(__name__)

class MockDataProviderException(Exception):
    pass

class MockDataProvider():
    """ Data provider for test operations """
    block_data = {}

    @classmethod
    def print_data(cls):
        print(dumps(cls.block_data, indent=4, sort_keys=True))

    @classmethod
    def add_block_data_from_directory(cls, dir_name):
        from fnmatch import fnmatch
        pattern = "*.json"
        for path, _, files in os.walk(dir_name):
            for name in files:
                if fnmatch(name, pattern):
                    cls.add_block_data_from_file(os.path.join(path, name))

    @classmethod
    def add_block_data_from_file(cls, file_name):
        raise NotImplementedError("add_block_data_from_file is not implemented")

    @classmethod
    def load_block_data(cls, data_path):
        if os.path.isdir(data_path):
            log.warning("Loading mock ops data from directory: {}".format(data_path))
            cls.add_block_data_from_directory(data_path)
        else:
            log.warning("Loading mock ops data from file: {}".format(data_path))
            cls.add_block_data_from_file(data_path)
