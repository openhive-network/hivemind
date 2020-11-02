""" Data provider for test vops """
import logging
import os
from hive.indexer.mock_data_provider import MockDataProvider

log = logging.getLogger(__name__)

class MockVopsProvider(MockDataProvider):
    """ Data provider for test vops """
    @classmethod
    def load_block_data(cls, data_path):
        if os.path.isdir(data_path):
            log.warning("Loading mock virtual ops data from directory: {}".format(data_path))
            cls.add_block_data_from_directory(data_path)
        else:
            log.warning("Loading mock virtual ops data from file: {}".format(data_path))
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
        cls.add_block_data(data)

    @classmethod
    def add_block_data(cls, data):
        if 'ops' in data:
            if 'ops' in cls.block_data:
                cls.block_data['ops'].extend(data['ops'])
            else:
                cls.block_data['ops'] = data['ops']

        if 'ops_by_block' in data:
            if 'ops_by_block' not in cls.block_data:
                cls.block_data['ops_by_block'] = []

        for ops in data['ops_by_block']:
            for obb_ops in cls.block_data['ops_by_block']:
                if ops['block'] == obb_ops['block']:
                    obb_ops['ops'].extend(ops['ops'])

    @classmethod
    def get_block_data(cls, block_num):
        ret = {}
        if 'ops' in cls.block_data:
            for ops in cls.block_data['ops']:
                if ops['block'] == block_num:
                    ret['timestamp'] = ops['timestamp']
                    if 'ops' in ret:
                        ret['ops'].append(ops)
                    else:
                        ret['ops'] = [ops]
        if 'ops_by_block' in cls.block_data:
            for ops in cls.block_data['ops_by_block']:
                if ops['block'] == block_num:
                    ret['timestamp'] = ops['timestamp']
                    if 'ops_by_block' in ret:
                        ret['ops_by_block'].extend(ops['ops'])
                    else:
                        ret['ops_by_block'] = ops['ops']
        return ret
