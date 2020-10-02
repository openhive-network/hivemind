"""Main custom_json op handler."""

import logging

from funcy.seqs import first, second
from hive.db.adapter import Db

from hive.indexer.follow import Follow
from hive.indexer.reblog import Reblog
from hive.indexer.notify import Notify

from hive.indexer.community import process_json_community_op, START_BLOCK
from hive.utils.normalize import load_json_key
from hive.utils.json import valid_op_json, valid_date, valid_command, valid_keys

from hive.utils.stats import OPStatusManager as OPSM

DB = Db.instance()

log = logging.getLogger(__name__)

def _get_auth(op):
    """get account name submitting a custom_json op.

    Hive custom_json op processing requires `required_posting_auths`
    is always used and length 1. It may be that some ops will require
    `required_active_auths` in the future. For now, these are ignored.
    """
    if op['required_auths']:
        return None
    if len(op['required_posting_auths']) != 1:
        log.warning("unexpected auths: %s", op)
        return None
    return op['required_posting_auths'][0]

class CustomOp:
    """Processes custom ops and dispatches updates."""

    is_load_mock_data = False

    @classmethod
    def process_ops(cls, ops, block_num, block_date):
        """Given a list of operation in block, filter and process them."""
        for op in ops:
            start = OPSM.start()
            opName = str(op['id']) + ( '-ignored' if op['id'] not in ['follow', 'community', 'notify', 'reblog'] else '' )

            account = _get_auth(op)
            if not account:
                continue

            op_json = load_json_key(op, 'json')

            if not cls.is_load_mock_data:
              if op['id'] == 'follow':
                  if block_num < 6000000 and not isinstance(op_json, list):
                      op_json = ['follow', op_json]  # legacy compat
                  cls._process_legacy(account, op_json, block_date, block_num)
              elif op['id'] == 'reblog':
                  if block_num < 6000000 and not isinstance(op_json, list):
                      op_json = ['reblog', op_json]  # legacy compat
                  cls._process_legacy(account, op_json, block_date, block_num)
              elif op['id'] == 'community':
                  if block_num > START_BLOCK:
                      process_json_community_op(account, op_json, block_date, block_num)
              elif op['id'] == 'notify':
                  cls._process_notify(account, op_json, block_date)
            else:
              if op['id'] == 'notify':
                cls._process_notify(account, op_json, block_date)
              elif op['id'] == 'community':
                process_json_community_op(account, op_json, block_date, block_num)

            OPSM.op_stats(opName, OPSM.stop(start))

    @classmethod
    def _process_notify(cls, account, op_json, block_date):
        """Handle legacy 'follow' plugin ops (follow/mute/clear, reblog)

        mark_read {date: {type: 'date'}}
        """
        try:
            command, payload = valid_op_json(op_json)
            valid_command(command, valid=('setLastRead'))
            if command == 'setLastRead':
                valid_keys(payload, required=['date'])
                date = valid_date(payload['date'])
                assert date <= block_date
                Notify.set_lastread(account, date)
        except AssertionError as e:
            log.warning("notify op fail: %s in %s", e, op_json)

    @classmethod
    def _process_legacy(cls, account, op_json, block_date, block_num):
        """Handle legacy 'follow' plugin ops (follow/mute/clear, reblog)

        follow {follower: {type: 'account'},
                following: {type: 'account'},
                what: {type: 'list'}}
        reblog {account: {type: 'account'},
                author: {type: 'account'},
                permlink: {type: 'permlink'},
                delete: {type: 'str', optional: True}}
        """
        if not isinstance(op_json, list):
            return
        if len(op_json) != 2:
            return
        if first(op_json) not in ['follow', 'reblog']:
            return
        if not isinstance(second(op_json), dict):
            return

        cmd, op_json = op_json  # ['follow', {data...}]
        if cmd == 'follow':
            Follow.follow_op(account, op_json, block_date, block_num)
        elif cmd == 'reblog':
            Reblog.reblog_op(account, op_json, block_date, block_num)
