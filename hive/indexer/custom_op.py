"""Main custom_json op handler."""
import logging

from funcy.seqs import first, second
from hive.db.adapter import Db
from hive.db.db_state import DbState

from hive.indexer.accounts import Accounts
from hive.indexer.posts import Posts
from hive.indexer.feed_cache import FeedCache
from hive.indexer.follow import Follow
from hive.indexer.notify import Notify

from hive.indexer.community import process_json_community_op, START_BLOCK
from hive.utils.normalize import load_json_key
from hive.utils.json import valid_op_json, valid_date, valid_command, valid_keys

DB = Db.instance()

log = logging.getLogger(__name__)

def _get_auth(op):
    """get account name submitting a custom_json op.

    Hive custom_json op processing requires `required_posting_auths`
    is always used and length 1. It may be that some ops will require
    `required_active_auths` in the future. For now, these are ignored.
    """
    if op['required_auths']:
        log.warning("unexpected active auths: %s", op)
        return None
    if len(op['required_posting_auths']) != 1:
        log.warning("unexpected auths: %s", op)
        return None
    return op['required_posting_auths'][0]

class CustomOp:
    """Processes custom ops and dispatches updates."""

    @classmethod
    def process_ops(cls, ops, block_num, block_date):
        ops_stats = {}

        """Given a list of operation in block, filter and process them."""
        for op in ops:
            if op['id'] not in ['follow', 'community', 'notify']:
                opName = str(op['id']) + '-ignored'
                if(opName  in ops_stats):
                    ops_stats[opName] += 1
                else:
                    ops_stats[opName] = 1
                continue

            if(op['id'] in ops_stats):
                ops_stats[op['id']] += 1
            else:
                ops_stats[op['id']] = 1

            account = _get_auth(op)
            if not account:
                continue

            op_json = load_json_key(op, 'json')
            if op['id'] == 'follow':
                if block_num < 6000000 and not isinstance(op_json, list):
                    op_json = ['follow', op_json]  # legacy compat
                cls._process_legacy(account, op_json, block_date)
            elif op['id'] == 'community':
                if block_num > START_BLOCK:
                    process_json_community_op(account, op_json, block_date)
            elif op['id'] == 'notify':
                cls._process_notify(account, op_json, block_date)
        return ops_stats

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
    def _process_legacy(cls, account, op_json, block_date):
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
            Follow.follow_op(account, op_json, block_date)
        elif cmd == 'reblog':
            cls.reblog(account, op_json, block_date)

    @classmethod
    def reblog(cls, account, op_json, block_date):
        """Handle legacy 'reblog' op"""
        if ('account' not in op_json
                or 'author' not in op_json
                or 'permlink' not in op_json):
            return
        blogger = op_json['account']
        author = op_json['author']
        permlink = op_json['permlink']

        if blogger != account:
            return  # impersonation
        if not all(map(Accounts.exists, [author, blogger])):
            return

        if 'delete' in op_json and op_json['delete'] == 'delete':
            sql = """
                  WITH processing_set AS (
                    SELECT hp.id as post_id, ha.id as account_id
                    FROM hive_posts hp
                    INNER JOIN hive_accounts ha ON hp.author_id = ha.id
                    INNER JOIN hive_permlink_data hpd ON hp.permlink_id = hpd.id
                    WHERE ha.name = :a AND hpd.permlink = :permlink AND hp.depth <= 0
                  )
                  DELETE FROM hive_reblogs AS hr 
                  WHERE hr.account = :a AND hr.post_id IN (SELECT ps.post_id FROM processing_set ps)
                  RETURNING hr.post_id, (SELECT ps.account_id FROM processing_set ps) AS account_id
                  """

            row = DB.query_row(sql, a=blogger, permlink=permlink)
            if row is None:
                log.debug("reblog: post not found: %s/%s", author, permlink)
                return

            if not DbState.is_initial_sync():
                result = dict(row)
                FeedCache.delete(result['post_id'], result['account_id'])

        else:
            sql = """
                  INSERT INTO hive_reblogs (account, post_id, created_at)
                  SELECT ha.name, hp.id, :date
                  FROM hive_accounts ha
                  INNER JOIN hive_posts hp ON hp.author_id = ha.id
                  INNER JOIN hive_permlink_data hpd ON hpd.id = hp.permlink_id
                  WHERE ha.name = :a AND hpd.permlink = :p
                  ON CONFLICT (account, post_id) DO NOTHING
                  RETURNING post_id 
                  """
            row = DB.query_row(sql, a=blogger, p=permlink, date=block_date)
            if not DbState.is_initial_sync():
                author_id = Accounts.get_id(author)
                blogger_id = Accounts.get_id(blogger)
                if row is not None:
                    result = dict(row)
                    post_id = result['post_id']
                    FeedCache.insert(post_id, blogger_id, block_date)
                    Notify('reblog', src_id=blogger_id, dst_id=author_id,
                        post_id=post_id, when=block_date,
                        score=Accounts.default_score(blogger)).write()
