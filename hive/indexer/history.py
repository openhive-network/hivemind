""" Class for reblog operations """

import logging

from hive.db.adapter import Db
from hive.db.db_state import DbState

from hive.indexer.accounts import Accounts
from hive.indexer.feed_cache import FeedCache
from hive.indexer.notify import Notify
from hive.indexer.db_adapter_holder import DbAdapterHolder
from collections import OrderedDict
from queue import Queue
from json import dumps
from hive.utils.normalize import escape_characters
import sqlalchemy as sa
from hive.utils.stats import PreProcessingStatusManager as PPSM
from hive.utils.operation_extractor import extract, FIELDS_WITH_NAMES

log = logging.getLogger(__name__)


def range_generator( coll : list, item_count : int):
    if item_count >= len(coll):
        yield coll
        return

    lbound = 0
    while lbound + item_count < len(coll):
        ret = []
        for v in coll:
            ret.append(list(v[lbound:lbound + item_count]))
        lbound += item_count
        yield ret
    yield list(coll[lbound:])
    return

class NewOperationFlushObject():
    def __init__(self, op_name):
        self.op_name = op_name

    def __str__(self):
        return f"( '{self.op_name}' )"

    def __repr__(self):
        return self.__str__()

'''

	TODO: 

		* [ OK ] Create inserting of transactions, same as new operations
		* [ OK ] Separate adding of additional information from adding history records
		* [ OK ] Test
		* [    ] Add important information extraction
		* [    ] Add flag to enable this part (by defalt should be disabled)

'''



class HistoryFlushObject():

    def __init__(self, block_num : int, trx_id : int, op_pos_in_tx : int, op_id : int, data : dict = {} ):
        assert ( trx_id is not None and 
                op_pos_in_tx is not None and
                op_id is not None )

        self.trx_id = trx_id
        self.position = op_pos_in_tx
        self.op_id = op_id
        self.data = data if data is not None else {}
        self.block_num = block_num

        self.__accs : list = None

    def missing_id(self) -> bool:
        return type(self.op_id) == type(str())

    def __get_op_pos(self):
        assert self.position is not None, f"position: {self.position}"
        return self.position

    def __get_tx_id(self):
        assert self.trx_id is not None, f"trx_id: {self.trx_id}"
        return self.trx_id

    def __get_op_id(self):
        assert self.op_id is not None, f"op_id: {self.op_id}"
        return self.op_id


    def get_insert_sql(self, accounts = '{}', info = "") -> list:
        return [
            f"({self.__get_tx_id()}, {self.__get_op_pos()}, {self.__get_op_id()}, '{accounts}' /* block num: {self.block_num} */ )", 
            f"({self.__get_tx_id()}, {self.__get_op_pos()}, {escape_characters('')} /* block num: {self.block_num} */)"
        ]

    def get_accounts(self) -> list:
        
        if self.__accs is None:
            self.__accs = extract(self.data, FIELDS_WITH_NAMES)
        return self.__accs

class History(DbAdapterHolder):
    """ Class for history operations """
    new_operations_to_flush = {}
    history_items_to_flush = []

    # cache like storage
    op_ids = OrderedDict()
    trx_hash_id = dict()

    @classmethod
    def archive_op(cls, block_num, trx_hash, op_type, op):

        op_id = cls.op_ids.get(op_type, op_type)
        if op_id == op_type:
            cls.new_operations_to_flush[op_type] = NewOperationFlushObject(op_type)

        if trx_hash in cls.trx_hash_id.keys():
            cls.trx_hash_id[trx_hash][1] += 1
        else:
            cls.trx_hash_id[trx_hash] = [block_num, 1]

        cls.history_items_to_flush.append(HistoryFlushObject( block_num, trx_hash, cls.trx_hash_id[trx_hash][1], op_id, op ))

    @classmethod
    def update_op_ids(cls):
        ret = cls.db.query_all("SELECT op_name, op_name_id FROM hive_operation_names")
        for _k, _v in ret:
            cls.op_ids[_k] = _v

    @classmethod
    def flush(cls):
        # adding new operations
        ret_count = 0
        if len(cls.op_ids) == 0:
            cls.update_op_ids()

        if len(cls.new_operations_to_flush) > 0:
            cls.db.query_no_return( f"""INSERT INTO hive_operation_names(op_name) VALUES {",".join([ str(op) for op in cls.new_operations_to_flush.values() ])} ON CONFLICT DO NOTHING""" )
            ret_count += len(cls.new_operations_to_flush)
            cls.new_operations_to_flush.clear()
            cls.update_op_ids()

        # setting up counter
        if len(cls.history_items_to_flush) == 0:
            return ret_count
        else:
            ret_count += len(cls.history_items_to_flush)
            ret_count += len(cls.trx_hash_id)

        start = PPSM.start()
        # gather required accs
        accs = set()
        for v in cls.history_items_to_flush:
            tmp_acc = set(v.get_accounts())
            if len(accs) == 0:
                accs = tmp_acc
            else:
                accs.update(tmp_acc)

        # gather accs from db
        pre_accs = [f"'{x}'" for x in accs]
        db_ret = cls.db.query_all(f"SELECT id, name FROM hive_accounts WHERE name IN ({ ', '.join(pre_accs) })")
        accs = dict()
        for key_id, value_name in db_ret:
            accs[value_name] = key_id

        # gather and insert trxs from db
        pre_trx = [f"('{tx}', /* block number: */ {v[0]}, {v[1]})" for tx, v in cls.trx_hash_id.items()]
        db_ret = cls.db.query_all( f"INSERT INTO hive_transactions(trx_hash, block_num, op_count) VALUES{ ','.join(pre_trx)} RETURNING trx_hash, trx_id")
        pre_trx.clear()
        for trx_hash, trx_id in db_ret:
            cls.trx_hash_id[trx_hash] = int(trx_id) # override block_number to trx_id

        # helper
        def get_account_ids( op : HistoryFlushObject ) -> list:
            ret = []
            for acc in op.get_accounts():
                ret.append(str(accs[acc]))
            return ret

        # core preprocessing items to flush
        values = [[], []]
        cnt = 0
        for v in cls.history_items_to_flush:
            v.trx_id = cls.trx_hash_id[v.trx_id]
            assert type(v.trx_id) != type(list())
            if v.missing_id():
                assert v.op_id in cls.op_ids.keys()
                v.op_id = cls.op_ids[v.op_id]
            sqls = v.get_insert_sql( "{" + ", ".join(get_account_ids(v)) + "}" )
            for i in range(0, len(sqls)):
                values[i].append(sqls[i])
        
        PPSM.preprocess_stat( 'preprocessing_history_stats', PPSM.stop(start), len(cls.history_items_to_flush) )

        # insert to db
        for ops, spec_ops in range_generator(values, 1000):
            cls.db.query_no_return(f"""INSERT INTO hive_operations( trx_id, position, op_name_id, participants ) VALUES { ",".join(ops) }""")
            cls.db.query_no_return(f"""INSERT INTO hive_operations_details( trx_id, op_position, important_info ) VALUES { ",".join(spec_ops) } ON CONFLICT DO NOTHING""")

        cls.history_items_to_flush.clear()
        cls.trx_hash_id.clear()
        return ret_count
