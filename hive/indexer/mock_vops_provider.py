""" Data provider for test vops """
import logging
import os
from hive.indexer.mock_data_provider import MockDataProvider

log = logging.getLogger(__name__)

class MockVopsProvider(MockDataProvider):
    """ Data provider for test vops """
    block_data = {
        'ops' : {},
        'ops_by_block' : {}
    }
    @classmethod
    def load_block_data(cls, data_path):
        #clear old data and prepare container
        cls.block_data.clear()
        cls.block_data['ops'] = {}
        cls.block_data['ops_by_block'] = {}

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
            for op in data['ops']:
                if 'ops' in cls.block_data and op['block'] in cls.block_data['ops']:
                    cls.block_data['ops'][op['block']].append(op)
                else:
                    cls.block_data['ops'][op['block']] = [op]

        if 'ops_by_block' in data:
            for ops in data['ops_by_block']:
                if 'ops_by_block' in cls.block_data and ops['block'] in cls.block_data['ops_by_block']:
                    cls.block_data['ops_by_block'][ops['block']].extend(ops['ops'])
                else:
                    cls.block_data['ops_by_block'][ops['block']] = ops

    @classmethod
    def get_block_data(cls, block_num):
        ret = {}
        if 'ops' in cls.block_data and block_num in cls.block_data['ops']:
            data = cls.block_data['ops'][block_num]
            if data:
                ret['timestamp'] = data[0]['timestamp']
                if 'ops' in ret:
                    ret['ops'].extend([op['op'] for op in data])
                else:
                    ret['ops'] = [op['op'] for op in data]

        if 'ops_by_block' in cls.block_data and block_num in cls.block_data['ops_by_block']:
            data = cls.block_data['ops_by_block'][block_num]
            if data:
                ret['timestamp'] = data['timestamp']
                if 'ops_by_block' in ret:
                    ret['ops_by_block'].extend([ops['op'] for ops in data['ops']])
                else:
                    ret['ops_by_block'] = [ops['op'] for ops in data['ops']]
        return ret

    @classmethod
    def add_mock_vops(cls, ret, from_block, end_block):
        # dont do anyting when there is no block data
        if not cls.block_data['ops_by_block'] and not cls.block_data['ops']:
            return
        for block_num in range(from_block, end_block):
            mock_vops = cls.get_block_data(block_num)
            if mock_vops:
                if block_num in ret:
                    if 'ops_by_block' in mock_vops:
                        ret[block_num]['ops'].extend(mock_vops['ops_by_block'])
                    if 'ops' in mock_vops:
                        ret[block_num]['ops'].extend(mock_vops['ops'])
                else:
                    if 'ops' in mock_vops:
                        ret[block_num] = {'timestamp':mock_vops['timestamp'], "ops" : mock_vops['ops']}
                    if 'ops_by_block' in mock_vops:
                        ret[block_num] = {'timestamp':mock_vops['timestamp'], "ops" : mock_vops['ops_by_block']}

