""" Data provider for test vops """
import logging
from hive.indexer.mock_data_provider import MockDataProvider

log = logging.getLogger(__name__)

class MockVopsProvider(MockDataProvider):
    """ Data provider for test vops """
    @classmethod
    def get_block_data(cls, block_num):
        ret = {'timestamp': "", 'ops' : [], 'ops_by_block' : []}
        if cls.block_data:
            for ops in cls.block_data['ops']:
                if ops['block'] == block_num:
                    ret['timestamp'] = ops['timestamp']
                    ret['ops'].append(ops)
            for ops in cls.block_data['ops_by_block']:
                if ops['block'] == block_num:
                    ret['timestamp'] = ops['timestamp']
                    ret['ops_by_block'].extend(ops['ops'])
        return ret
