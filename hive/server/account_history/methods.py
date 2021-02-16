# pylint: disable=too-many-arguments,line-too-long,too-many-lines
from enum import Enum

from hive.server.common.helpers import return_error_info, valid_limit, valid_account
import hive.server.account_history.objects as objects
from hive.utils.normalize import escape_characters

LIMIT_MAX = 1000
LIMIT_DEFAULT = LIMIT_MAX
OPERATION_BEGIN_DEFAULT = -1

@return_error_info
async def enum_virtual_ops(
  context, 
  block_range_begin: int, 
  block_range_end: int, 
  include_reversible : bool = None, 
  group_by_block : bool = None,
  operation_begin : int = None,
  limit : int = LIMIT_DEFAULT,
  filter : int = None
):
  operation_begin = OPERATION_BEGIN_DEFAULT if operation_begin is None else operation_begin
  limit = valid_limit(limit, LIMIT_MAX, LIMIT_DEFAULT)

  sql = "SELECT * FROM ah_get_enum_virtual_ops( NULL::INT[], :block_range_begin, :block_range_end, :operation_begin, :limit ) ORDER BY _block, _trx_in_block, _op_in_trx"
  db = context['ah_db']

  rows = await db.query_all(sql, block_range_begin=block_range_begin, block_range_end=block_range_end, operation_begin=operation_begin, limit=limit)
  return objects.get_enum_virtual_ops(rows, limit, group_by_block)


@return_error_info
async def get_account_history(
  context, 
  account : str, 
  start : int, 
  limit : int,
  include_reversible : bool = None,
  operation_filter_low : int = None,
  operation_filter_high : int = None
):
  valid_account(account, True)
  limit = valid_limit(limit, LIMIT_MAX, LIMIT_DEFAULT)

  sql = "select * from ah_get_account_history( NULL::INT[], :account, :start, :limit ) ORDER BY _block, _trx_in_block, _op_in_trx, _virtual_op DESC"
  db = context['ah_db']
  rows = await db.query_all(sql, account=account, start=start, limit=limit)
  return objects.get_account_history(rows)

@return_error_info
async def get_ops_in_block(
  context, 
  block_num : int, 
  only_virtual : bool,
  include_reversible : bool = None
):
  sql = "select * from ah_get_ops_in_block( :block_num, :virtual_mode) order by _trx_in_block, _virtual_op;"

  db = context['ah_db']
  rows = await db.query_all(sql, block_num=block_num, virtual_mode=only_virtual)
  return objects.get_ops_in_block( rows, block_num )