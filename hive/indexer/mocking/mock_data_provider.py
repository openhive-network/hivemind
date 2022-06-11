""" Data provider for test operations """
from json import dumps
import logging
import os
from pathlib import Path

log = logging.getLogger(__name__)


class MockDataProviderException(Exception):
    pass


class MockDataProvider:
    """Data provider for test operations"""

    block_data = {}

    @classmethod
    def print_data(cls):
        print(dumps(cls.block_data, indent=4, sort_keys=True))

    @classmethod
    def add_block_data_from_directory(cls, dir_name):
        pattern = "*.json"
        for path in Path(dir_name).rglob(pattern):
            log.warning(f"Loading mock ops data from file: {path}")
            cls.add_block_data_from_file(path)

    @classmethod
    def add_block_data_from_file(cls, file_name):
        raise NotImplementedError("add_block_data_from_file is not implemented")

    @classmethod
    def load_block_data(cls, data_path):
        if os.path.isdir(data_path):
            log.warning(f"Loading mock ops data from directory: {data_path}")
            cls.add_block_data_from_directory(data_path)
        else:
            log.warning(f"Loading mock ops data from file: {data_path}")
            cls.add_block_data_from_file(data_path)
