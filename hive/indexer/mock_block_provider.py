""" Data provider for test operations """
import logging
import os
import dateutil.parser
from hive.db.adapter import Db

from hive.indexer.mock_data_provider import MockDataProvider, MockDataProviderException

log = logging.getLogger(__name__)

import datetime

def get_head_num_and_timestamp():
    DB = Db.instance()
    sql = "SELECT num, created_at FROM hive_blocks ORDER BY num DESC LIMIT 1"
    ret = DB.query_row(sql)
    if ret:
        return (ret["num"], ret["created_at"])
    return (1, dateutil.parser.isoparse("2016-03-24T16:05:00"))

class MockBlockProvider(MockDataProvider):

    min_block = 0
    max_block = 0

    """ Data provider for test ops """
    @classmethod
    def load_block_data(cls, data_path):
        cls.block_data.clear()
        cls.min_block = 0
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
        if block_num < cls.min_block:
            cls.min_block = block_num

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

    @classmethod
    def make_block_id(cls, block_num):
        return "{:08x}00000000000000000000000000000000".format(block_num)

    @classmethod
    def make_block_timestamp(cls, block_num):
        ref_num, ref_time = get_head_num_and_timestamp()
        block_delta = block_num - ref_num
        time_delta = datetime.timedelta(days=0, seconds=block_delta*3, microseconds=0, milliseconds=0, minutes=0, hours=0, weeks=0)
        ret_time = ref_time + time_delta
        return ret_time.replace(microsecond=0).isoformat()

    @classmethod 
    def make_empty_block(cls, block_num, witness="initminer"):
        block_data = {
            "previous": cls.make_block_id(block_num - 1),
            "timestamp": cls.make_block_timestamp(block_num),
            "witness": witness,
            "transaction_merkle_root": "0000000000000000000000000000000000000000",
            "extensions": [],
            "witness_signature": "",
            "transactions": [],
            "block_id": cls.make_block_id(block_num),
            "signing_key": "",
            "transaction_ids": []
            }
        # supply enough blocks to fill block queue with empty blocks only
        # throw exception if there is no more data to serve
        if block_num > cls.min_block and block_num < cls.max_block + 3:
            return block_data
        return None

