""" Data provider for test operations """
import datetime
import logging

from hive.indexer.mock_data_provider import MockDataProvider

log = logging.getLogger(__name__)


class MockBlockProvider(MockDataProvider):
    """Data provider for test ops"""

    min_block = 0
    max_block = 0

    last_real_block_num = 1
    last_real_block_id = ""
    last_real_block_time = datetime.datetime.fromisoformat("2016-03-24T16:05:00")

    @classmethod
    def set_last_real_block_num_date(cls, block_num, block_date, block_id):
        if cls.last_real_block_num > block_num:
            log.error(
                f"Incoming block has lower number than previous one: old {cls.last_real_block_num}, new {block_num}"
            )
        cls.last_real_block_num = int(block_num)
        cls.last_real_block_id = block_id
        new_date = datetime.datetime.fromisoformat(block_date)
        if cls.last_real_block_time > new_date:
            log.error(
                f"Incoming block {block_num} has older timestamp than previous one: old {cls.last_real_block_time}, new {new_date}"
            )
        cls.last_real_block_time = new_date

    @classmethod
    def add_block_data_from_file(cls, file_name):
        from json import load

        data = {}
        with open(file_name, "r") as src:
            data = load(src)
        for block_num, block_content in data.items():
            cls.add_block_data(block_num, block_content)

    @classmethod
    def add_block_data(cls, _block_num, block_content):
        block_num = int(_block_num)

        if block_num > cls.max_block:
            cls.max_block = block_num
        if block_num < cls.min_block:
            cls.min_block = block_num

        if block_num in cls.block_data:
            # mocks contain only transactions - rest is taken either from original block
            # or from default empty mock; see also get_block_data below; note that we can't
            # supplement data with defaults here because they depend on last_real_block_...
            assert 'transactions' in cls.block_data[block_num]
            assert 'transactions' in block_content
            cls.block_data[block_num]['transactions'] = (
                cls.block_data[block_num]['transactions'] + block_content['transactions']
            )
        else:
            cls.block_data[block_num] = dict(block_content)

    @classmethod
    def get_block_data(cls, block_num, make_on_empty=False):
        if (
            len(cls.block_data) == 0
        ):  # this means there are no mocks, so none should be returned (even with make_on_empty)
            return None

        data = cls.block_data.get(block_num, None)

        if data is not None:
            # supplement mock data with necessary (default) elements
            base = cls.make_empty_block(block_num)
            base['transactions'] = data['transactions']
            data = base
        elif make_on_empty:
            data = cls.make_empty_block(block_num)

        return data

    @classmethod
    def get_max_block_number(cls):
        return cls.max_block

    @classmethod
    def make_block_id(cls, block_num):
        if block_num == cls.last_real_block_num:
            return cls.last_real_block_id
        else:
            return f"{block_num:08x}00000000000000000000000000000000"

    @classmethod
    def make_block_timestamp(cls, block_num):
        block_delta = block_num - cls.last_real_block_num
        time_delta = datetime.timedelta(
            days=0, seconds=block_delta * 3, microseconds=0, milliseconds=0, minutes=0, hours=0, weeks=0
        )
        ret_time = cls.last_real_block_time + time_delta
        return ret_time.replace(microsecond=0).isoformat()

    @classmethod
    def make_empty_block(cls, block_num, witness="initminer"):
        fake_block = dict(
            {
                "previous": cls.make_block_id(block_num - 1),
                "timestamp": cls.make_block_timestamp(block_num),
                "witness": witness,
                "transaction_merkle_root": "0000000000000000000000000000000000000000",
                "extensions": [],
                "witness_signature": "",
                "transactions": [],
                "block_id": cls.make_block_id(block_num),
                "signing_key": "",
                "transaction_ids": [],
            }
        )
        # supply enough blocks to fill block queue with empty blocks only
        # throw exception if there is no more data to serve
        if cls.min_block < block_num < cls.max_block + 3:
            return fake_block
        return None
