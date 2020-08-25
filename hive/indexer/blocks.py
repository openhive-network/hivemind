"""Blocks processor."""

import logging
import json

from hive.db.adapter import Db

from hive.indexer.accounts import Accounts
from hive.indexer.posts import Posts
from hive.indexer.custom_op import CustomOp
from hive.indexer.payments import Payments
from hive.indexer.follow import Follow
from hive.indexer.votes import Votes
from hive.indexer.post_data_cache import PostDataCache
from hive.indexer.tags import Tags
from time import perf_counter

from hive.utils.stats import OPStatusManager as OPSM
from hive.utils.stats import FlushStatusManager as FSM
from hive.utils.trends import update_hot_and_tranding_for_block_range
from hive.utils.post_active import update_active_starting_from_posts_on_block

log = logging.getLogger(__name__)

DB = Db.instance()

class Blocks:
    """Processes blocks, dispatches work, manages `hive_blocks` table."""
    blocks_to_flush = []
    _head_block_date = None # timestamp of last fully processed block ("previous block")
    _current_block_date = None # timestamp of block currently being processes ("current block")

    def __init__(cls):
        head_date = cls.head_date()
        if(head_date == ''):
            cls._head_block_date = None
            cls._current_block_date = None
        else:
            cls._head_block_date = head_date
            cls._current_block_date = head_date

    @classmethod
    def head_num(cls):
        """Get hive's head block number."""
        sql = "SELECT num FROM hive_blocks ORDER BY num DESC LIMIT 1"
        return DB.query_one(sql) or 0

    @classmethod
    def head_date(cls):
        """Get hive's head block date."""
        sql = "SELECT created_at FROM hive_blocks ORDER BY num DESC LIMIT 1"
        return str(DB.query_one(sql) or '')

    @classmethod
    def process(cls, block, vops_in_block, hived):
        """Process a single block. Always wrap in a transaction!"""
        time_start = perf_counter()
        #assert is_trx_active(), "Block.process must be in a trx"
        ret = cls._process(block, vops_in_block, hived, is_initial_sync=False)
        cls._flush_blocks()
        PostDataCache.flush()
        Tags.flush()
        Votes.flush()
        Posts.flush()
        block_num = int(block['block_id'][:8], base=16)
        cls.on_live_blocks_processed( block_num, block_num )
        time_end = perf_counter()
        log.info("[PROCESS BLOCK] %fs", time_end - time_start)
        return ret

    @classmethod
    def process_multi(cls, blocks, vops, hived, is_initial_sync=False):
        """Batch-process blocks; wrapped in a transaction."""
        time_start = OPSM.start()
        DB.query("START TRANSACTION")

        last_num = 0
        first_block = -1
        try:
            for block in blocks:
                if first_block == -1:
                    first_block = int(block['block_id'][:8], base=16)
                last_num = cls._process(block, vops, hived, is_initial_sync)
        except Exception as e:
            log.error("exception encountered block %d", last_num + 1)
            raise e

        # Follows flushing needs to be atomic because recounts are
        # expensive. So is tracking follows at all; hence we track
        # deltas in memory and update follow/er counts in bulk.

        flush_time = FSM.start()
        def register_time(f_time, name, pushed):
            assert pushed is not None
            FSM.flush_stat(name, FSM.stop(f_time), pushed)
            return FSM.start()

        log.info("#############################################################################")
        flush_time = register_time(flush_time, "Blocks", cls._flush_blocks())
        flush_time = register_time(flush_time, "PostDataCache", PostDataCache.flush())
        flush_time = register_time(flush_time, "Tags", Tags.flush())
        flush_time = register_time(flush_time, "Votes", Votes.flush())
        folllow_items = len(Follow.follow_items_to_flush) + Follow.flush(trx=False)
        flush_time = register_time(flush_time, "Follow", folllow_items)
        flush_time = register_time(flush_time, "Posts", Posts.flush())

        if (not is_initial_sync) and (first_block > -1):
            cls.on_live_blocks_processed( first_block, last_num )

        DB.query("COMMIT")

        log.info(f"[PROCESS MULTI] {len(blocks)} blocks in {OPSM.stop(time_start) :.4f}s")

    @staticmethod
    def prepare_vops(comment_payout_ops, vopsList, date, block_num):
        vote_ops = {}

        ineffective_deleted_ops = {}
        registered_ops_stats = [ 'author_reward_operation', 'comment_reward_operation', 'effective_comment_vote_operation', 'comment_payout_update_operation', 'ineffective_delete_comment_operation']

        for vop in vopsList:
            start = OPSM.start()
            key = None
            val = None

            op_type = vop['type']
            op_value = vop['value']
            op_value['block_num'] = block_num
            key = "{}/{}".format(op_value['author'], op_value['permlink'])

            if op_type == 'author_reward_operation':
                if key not in comment_payout_ops:
                    comment_payout_ops[key] = { 'author_reward_operation':None, 'comment_reward_operation':None, 'effective_comment_vote_operation':None, 'comment_payout_update_operation':None, 'date' : date }

                comment_payout_ops[key][op_type] = op_value

            elif op_type == 'comment_reward_operation':
                if key not in comment_payout_ops:
                    comment_payout_ops[key] = { 'author_reward_operation':None, 'comment_reward_operation':None, 'effective_comment_vote_operation':None, 'comment_payout_update_operation':None, 'date' : date }

                comment_payout_ops[key]['effective_comment_vote_operation'] = None

                comment_payout_ops[key][op_type] = op_value

            elif op_type == 'effective_comment_vote_operation':
                key_vote = "{}/{}/{}".format(op_value['voter'], op_value['author'], op_value['permlink'])
                vote_ops[ key_vote ] = op_value

                if key not in comment_payout_ops:
                    comment_payout_ops[key] = { 'author_reward_operation':None, 'comment_reward_operation':None, 'effective_comment_vote_operation':None, 'comment_payout_update_operation':None, 'date' : date }

                comment_payout_ops[key][op_type] = op_value

            elif op_type == 'comment_payout_update_operation':
                if key not in comment_payout_ops:
                    comment_payout_ops[key] = { 'author_reward_operation':None, 'comment_reward_operation':None, 'effective_comment_vote_operation':None, 'comment_payout_update_operation':None, 'date' : date }

                comment_payout_ops[key][op_type] = op_value
            elif op_type == 'ineffective_delete_comment_operation':
                ineffective_deleted_ops[key] = {}

            if op_type in registered_ops_stats:
                OPSM.op_stats(op_type, OPSM.stop(start))

        return (vote_ops, ineffective_deleted_ops)


    @classmethod
    def _process(cls, block, virtual_operations, hived, is_initial_sync=False):
        """Process a single block. Assumes a trx is open."""
        #pylint: disable=too-many-branches
        num = cls._push(block)
        cls._current_block_date = block['timestamp']

        # head block date shall point to last imported block (not yet current one) to conform hived behavior.
        # that's why operations processed by node are included in the block being currently produced, so its processing time is equal to last produced block.
        # unfortunately it is not true to all operations, most likely in case of dates that used to come from
        # FatNode where it supplemented it with its-current head block, since it was already past block processing,
        # it saw later block (equal to _current_block_date here)
        if cls._head_block_date is None:
            cls._head_block_date = cls._current_block_date

        vote_ops                = None
        comment_payout_stats    = None
        ineffective_deleted_ops = None

        if is_initial_sync:
            if num in virtual_operations:
                (vote_ops, ineffective_deleted_ops ) = Blocks.prepare_vops(Posts.comment_payout_ops, virtual_operations[num], cls._current_block_date, num)
        else:
            vops = hived.get_virtual_operations(num)
            (vote_ops, ineffective_deleted_ops ) = Blocks.prepare_vops(Posts.comment_payout_ops, vops, cls._current_block_date, num)

        json_ops = []
        for tx_idx, tx in enumerate(block['transactions']):
            for operation in tx['operations']:
                start = OPSM.start()
                op_type = operation['type']
                op = operation['value']

                assert 'block_num' not in op
                op['block_num'] = num

                account_name = None
                # account ops
                if op_type == 'pow_operation':
                    account_name = op['worker_account']
                elif op_type == 'pow2_operation':
                    account_name = op['work']['value']['input']['worker_account']
                elif op_type == 'account_create_operation':
                    account_name = op['new_account_name']
                elif op_type == 'account_create_with_delegation_operation':
                    account_name = op['new_account_name']
                elif op_type == 'create_claimed_account_operation':
                    account_name = op['new_account_name']

                Accounts.register(account_name, cls._head_block_date)

                # account metadata updates
                if op_type == 'account_update_operation':
                    if not is_initial_sync:
                        Accounts.dirty(op['account']) # full
                elif op_type == 'account_update2_operation':
                    if not is_initial_sync:
                        Accounts.dirty(op['account']) # full

                # post ops
                elif op_type == 'comment_operation':
                    Posts.comment_op(op, cls._head_block_date)
                    if not is_initial_sync:
                        Accounts.dirty(op['author']) # lite - stats
                elif op_type == 'delete_comment_operation':
                    key = "{}/{}".format(op['author'], op['permlink'])
                    if ( ineffective_deleted_ops is None ) or ( key not in ineffective_deleted_ops ):
                        Posts.delete_op(op)
                elif op_type == 'comment_options_operation':
                    Posts.comment_options_op(op)
                elif op_type == 'vote_operation':
                    if not is_initial_sync:
                        Accounts.dirty(op['author']) # lite - rep
                        Accounts.dirty(op['voter']) # lite - stats
                    Votes.vote_op(op, cls._head_block_date)

                # misc ops
                elif op_type == 'transfer_operation':
                    Payments.op_transfer(op, tx_idx, num, cls._head_block_date)
                elif op_type == 'custom_json_operation':
                    json_ops.append(op)

                if op_type != 'custom_json_operation':
                    OPSM.op_stats(op_type, OPSM.stop(start))

        # follow/reblog/community ops
        if json_ops:
            CustomOp.process_ops(json_ops, num, cls._head_block_date)

        if vote_ops is not None:
            for k, v in vote_ops.items():
                Votes.effective_comment_vote_op(k, v)

        cls._head_block_date = cls._current_block_date

        return num

    @classmethod
    def verify_head(cls, steem):
        """Perform a fork recovery check on startup."""
        hive_head = cls.head_num()
        if not hive_head:
            return

        # move backwards from head until hive/steem agree
        to_pop = []
        cursor = hive_head
        while True:
            assert hive_head - cursor < 25, "fork too deep"
            hive_block = cls._get(cursor)
            steem_hash = steem.get_block(cursor)['block_id']
            match = hive_block['hash'] == steem_hash
            log.info("[INIT] fork check. block %d: %s vs %s --- %s",
                     hive_block['num'], hive_block['hash'],
                     steem_hash, 'ok' if match else 'invalid')
            if match:
                break
            to_pop.append(hive_block)
            cursor -= 1

        if hive_head == cursor:
            return # no fork!

        log.error("[FORK] depth is %d; popping blocks %d - %d",
                  hive_head - cursor, cursor + 1, hive_head)

        # we should not attempt to recover from fork until it's safe
        fork_limit = steem.last_irreversible()
        assert cursor < fork_limit, "not proceeding until head is irreversible"

        cls._pop(to_pop)

    @classmethod
    def _get(cls, num):
        """Fetch a specific block."""
        sql = """SELECT num, created_at date, hash
                 FROM hive_blocks WHERE num = :num LIMIT 1"""
        return dict(DB.query_row(sql, num=num))

    @classmethod
    def _push(cls, block):
        """Insert a row in `hive_blocks`."""
        num = int(block['block_id'][:8], base=16)
        txs = block['transactions']
        cls.blocks_to_flush.append({
            'num': num,
            'hash': block['block_id'],
            'prev': block['previous'],
            'txs': len(txs),
            'ops': sum([len(tx['operations']) for tx in txs]),
            'date': block['timestamp']})
        return num

    @classmethod
    def _flush_blocks(cls):
        query = """
            INSERT INTO
                hive_blocks (num, hash, prev, txs, ops, created_at)
            VALUES
        """
        values = []
        for block in cls.blocks_to_flush:
            values.append("({}, '{}', '{}', {}, {}, '{}')".format(block['num'], block['hash'],
                                                                  block['prev'], block['txs'],
                                                                  block['ops'], block['date']))
        DB.query(query + ",".join(values))
        n = len(cls.blocks_to_flush)
        cls.blocks_to_flush = []
        return n

    @classmethod
    def _pop(cls, blocks):
        """Pop head blocks to navigate head to a point prior to fork.

        Without an undo database, there is a limit to how fully we can recover.

        If consistency is critical, run hive with TRAIL_BLOCKS=-1 to only index
        up to last irreversible. Otherwise use TRAIL_BLOCKS=2 to stay closer
        while avoiding the vast majority of microforks.

        As-is, there are a few caveats with the following strategy:

         - follow counts can get out of sync (hive needs to force-recount)
         - follow state could get out of sync (user-recoverable)

        For 1.5, also need to handle:

         - hive_communities
         - hive_members
         - hive_flags
         - hive_modlog
        """
        DB.query("START TRANSACTION")

        for block in blocks:
            num = block['num']
            date = block['date']
            log.warning("[FORK] popping block %d @ %s", num, date)
            assert num == cls.head_num(), "can only pop head block"

            # get all affected post_ids in this block
            sql = "SELECT id FROM hive_posts WHERE created_at >= :date"
            post_ids = tuple(DB.query_col(sql, date=date))

            # remove all recent records -- communities
            DB.query("DELETE FROM hive_notifs        WHERE created_at >= :date", date=date)
            DB.query("DELETE FROM hive_subscriptions WHERE created_at >= :date", date=date)
            DB.query("DELETE FROM hive_roles         WHERE created_at >= :date", date=date)
            DB.query("DELETE FROM hive_communities   WHERE created_at >= :date", date=date)

            # remove all recent records -- core
            DB.query("DELETE FROM hive_feed_cache  WHERE created_at >= :date", date=date)
            DB.query("DELETE FROM hive_reblogs     WHERE created_at >= :date", date=date)
            DB.query("DELETE FROM hive_follows     WHERE created_at >= :date", date=date)

            # remove posts: core, tags, cache entries
            if post_ids:
                DB.query("DELETE FROM hive_post_tags   WHERE post_id IN :ids", ids=post_ids)
                DB.query("DELETE FROM hive_posts       WHERE id      IN :ids", ids=post_ids)
                DB.query("DELETE FROM hive_post_data   WHERE id      IN :ids", ids=post_ids)

            DB.query("DELETE FROM hive_payments    WHERE block_num = :num", num=num)
            DB.query("DELETE FROM hive_blocks      WHERE num = :num", num=num)

        DB.query("COMMIT")
        log.warning("[FORK] recovery complete")
        # TODO: manually re-process here the blocks which were just popped.

    @classmethod
    def on_live_blocks_processed( cls, first_block, last_block ):
        """Is invoked when processing of block range is done and received
           informations from hived are already stored in db
        """

        update_hot_and_tranding_for_block_range( first_block, last_block )
        update_active_starting_from_posts_on_block( first_block, last_block )
