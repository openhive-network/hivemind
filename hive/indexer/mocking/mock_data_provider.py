"""Data provider for test operations"""

import logging
import os
from json import dumps
from pathlib import Path

log = logging.getLogger(__name__)


class MockDataProviderException(Exception):
    pass


class MockDataProvider:
    """Data provider for test operations"""

    block_data: dict[int, dict] = {}

    @classmethod
    def print_data(cls):
        print(dumps(cls.block_data, indent=4, sort_keys=True))

    @classmethod
    def add_block_data_from_directory(cls, dir_name: str) -> None:
        pattern = "*.json"
        # Ops of several files share blocks, in the order their files load: sorted,
        # not in the filesystem's directory order, so every host injects the same block.
        for path in sorted(Path(dir_name).rglob(pattern)):
            log.warning(f"Loading mock ops data from file: {path}")
            cls.add_block_data_from_file(path)

    @classmethod
    def add_block_data_from_file(cls, file_name: str | Path) -> None:
        raise NotImplementedError("add_block_data_from_file is not implemented")

    @classmethod
    def load_block_data(cls, data_path: str) -> None:
        if os.path.isdir(data_path):
            log.warning(f"Loading mock ops data from directory: {data_path}")
            cls.add_block_data_from_directory(data_path)
        else:
            log.warning(f"Loading mock ops data from file: {data_path}")
            cls.add_block_data_from_file(data_path)
