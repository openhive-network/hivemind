from hive.server.common.helpers import json_date
from hive.utils.normalize import sbd_amount, to_nai
from json import loads
from collections import OrderedDict




def account_history_object(row, block_num : int = None) -> dict:
    obj = {}

    obj["trx_id"]        = row['_trx_id']
    obj["block"]         = block_num if block_num is not None else int(row["_block"])
    obj["trx_in_block"]  = int(row[ "_trx_in_block" ])
    obj["op_in_trx"]     = int(row[ "_op_in_trx" ])
    obj["virtual_op"]    = int(row[ "_virtual_op" ])
    obj["timestamp"]     = row[ "_timestamp" ]
    obj["op"]            = loads(row[ "_value" ])
    obj["operation_id"]  = int(row[ "_operation_id" ])

    return obj

def api_operation_object(row) -> dict:
    return account_history_object(row)


def get_enum_virtual_ops( rows, limit : int, group_by_block : bool ) -> dict:
    """creates enum_virtual_ops return"""
    result = dict( ops = list(), ops_by_block = OrderedDict(), next_block_range_begin = 0, next_operation_begin   = 0 )

    is_paging_info = limit + 1 == len(rows)
    cnt = 0

    for row in rows:
        ah_obj = account_history_object(row)
        block_number = ah_obj['block']
        
        cnt += 1
        if is_paging_info and cnt == len(rows):
            result["next_block_range_begin"] = block_number
            result["next_operation_begin"] = ah_obj["operation_id"]
            break

        if group_by_block:
            if not ah_obj['block'] in result['ops_by_block']:
                result['ops_by_block'][block_number] = dict( timestamp=ah_obj['timestamp'], irreversible=True, ops=[ah_obj] )
            else:
                result['ops_by_block'][block_number]["ops"].append(ah_obj)

        else:
            result['ops'].append(ah_obj)

    result['ops_by_block'] = list(result['ops_by_block'].values())
    return result


def get_account_history(rows) -> dict:
    """creates account_history return"""
    result = OrderedDict()
    cnt = 0

    for row in rows:
        aoo = api_operation_object(row)
        result[ cnt ] = aoo
        cnt += 1

    return { "history": list(result.items()) }


def get_ops_in_block(rows) -> dict:
    """creates get_ops_in_block return"""
    result = OrderedDict()
    for row in rows:
        aoo = api_operation_object(row)
        result[ ( row[aoo["block"], aoo["trx_in_block"], aoo["op_in_trx"], aoo["virtual_op"]] )] = aoo
    return { "ops": result.values() }