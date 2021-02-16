from hive.server.common.helpers import json_date, raw_json
from hive.utils.normalize import sbd_amount, to_nai
from collections import OrderedDict

def api_operation_object(row, block_num = None, operation_id = None ):
    obj = {}

    obj['trx_id']       = row['_trx_id']
    obj['block']        = row[ '_block' ] if block_num is None else block_num
    obj['trx_in_block'] = row[ '_trx_in_block' ]
    obj['op_in_trx']    = row[ '_op_in_trx' ]
    obj['virtual_op']   = 1 if row[ '_virtual_op' ] else 0
    obj['timestamp']    = row[ '_timestamp' ]
    obj['op']           = raw_json(row[ '_value' ])
    obj['operation_id'] = row[ '_operation_id' ] if operation_id is None else operation_id

    return obj

def get_enum_virtual_ops( rows, limit : int, group_by_block : bool ):
    """creates enum_virtual_ops return"""
    result = dict( ops = list(), ops_by_block = OrderedDict(), next_block_range_begin = 0, next_operation_begin   = 0 )

    is_paging_info = limit + 1 == len(rows)
    cnt = 0

    for row in rows:
        block_num = row['_block']
        ah_obj = api_operation_object(row, block_num)

        cnt += 1
        if is_paging_info and cnt == len(rows):
            result["next_block_range_begin"] = block_num
            result["next_operation_begin"] = ah_obj["operation_id"]
            break

        if group_by_block:
            if not ah_obj['block'] in result['ops_by_block']:
                result['ops_by_block'][block_num] = dict( timestamp=ah_obj['timestamp'], irreversible=True, ops=[ah_obj] )
            else:
                result['ops_by_block'][block_num]["ops"].append(ah_obj)

        else:
            result['ops'].append(ah_obj)

    result['ops_by_block'] = list(result['ops_by_block'].values())
    return result

def get_account_history(rows):
    """creates account_history return"""
    ops = []

    for row in rows:
      obj = api_operation_object(row, None, 0)
      ops.append([row[ '_operation_id' ], obj])

    return { "history": ops }

def get_ops_in_block(rows, block_num):
    """creates get_ops_in_block return"""
    ops = []

    for row in rows:
      obj = api_operation_object(row, block_num)
      ops.append(obj)

    return { "ops": ops }
