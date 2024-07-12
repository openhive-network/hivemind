"""Main custom_json op handler."""

import logging

from funcy.seqs import first, second

from hive.db.adapter import Db
from hive.indexer.community import Community, process_json_community_op
from hive.indexer.follow import Follow
from hive.indexer.notify import Notify
from hive.indexer.reblog import Reblog
from hive.utils.json import valid_command, valid_date, valid_keys, valid_op_json
from hive.utils.normalize import load_json_key

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

    @classmethod
    def process_op(cls, op, block_num, block_date):
        opName = str(op['id']) + ('-ignored' if op['id'] not in ['follow', 'community', 'notify', 'reblog'] else '')

        account = _get_auth(op)
        if not account:
            return

        if op['id'] == 'follow':
            op_json = load_json_key(op, 'json')
            if block_num < 6000000 and not isinstance(op_json, list):
                op_json = ['follow', op_json]  # legacy compat
            cls._process_legacy(account, op_json, block_date, block_num)
        elif op['id'] == 'reblog':
            op_json = load_json_key(op, 'json')
            if block_num < 6000000 and not isinstance(op_json, list):
                op_json = ['reblog', op_json]  # legacy compat
            cls._process_legacy(account, op_json, block_date, block_num)
        elif op['id'] == 'community':
            if block_num > Community.start_block:
                op_json = load_json_key(op, 'json')
                process_json_community_op(account, op_json, block_date, block_num)
        elif op['id'] == 'notify':
            op_json = load_json_key(op, 'json')
            cls._process_notify(account, op_json, block_date)

    @classmethod
    def _process_notify(cls, account, op_json, block_date):
        """Handle legacy 'follow' plugin ops (follow/mute/clear, reblog)

        mark_read {date: {type: 'date'}}
        """
        try:
            command, payload = valid_op_json(op_json)
            valid_command(command, valid=('setLastRead'))
            if command == 'setLastRead':
                valid_keys(payload, optional=['date'])
                explicit_date = payload.get('date', None)
                if explicit_date is None:
                    date = block_date
                    log.info("setLastRead op: `%s' uses implicit head block time: `%s'", op_json, block_date)
                else:
                    date = valid_date(explicit_date)
                    if date > block_date:
                        log.warning(
                            "setLastRead::date: `%s' exceeds head block time. Correcting to head block time: `%s'",
                            date,
                            block_date,
                        )
                        date = block_date

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
