"""Blocks processor."""

import concurrent
from concurrent.futures import ThreadPoolExecutor
import logging
from time import perf_counter
from typing import Tuple

from hive.db.adapter import Db
from hive.indexer.accounts import Accounts
from hive.indexer.block import Block, Operation, OperationType, Transaction, VirtualOperationType
from hive.indexer.custom_op import CustomOp
from hive.indexer.follow import Follow
from hive.indexer.notify import Notify
from hive.indexer.payments import Payments
from hive.indexer.post_data_cache import PostDataCache
from hive.indexer.posts import Posts
from hive.indexer.reblog import Reblog
from hive.indexer.reputations import Reputations
from hive.indexer.votes import Votes
from hive.server.common.mentions import Mentions
from hive.server.common.payout_stats import PayoutStats
from hive.steem.client import SteemClient
from hive.utils.stats import FlushStatusManager as FSM
from hive.utils.stats import OPStatusManager as OPSM
from hive.utils.timer import time_it

log = logging.getLogger(__name__)

DB = Db.instance()


def time_collector(f):
    start_time = FSM.start()
    result = f()
    elapsed_time = FSM.stop(start_time)
    return result, elapsed_time


class Blocks:
    """Processes blocks, dispatches work, manages `hive_blocks` table."""

    blocks_to_flush = []
    _head_block_date = None
    _current_block_date = None
    _last_safe_cashout_block = 0
    _is_initial_sync = False

    _concurrent_flush = [
        ('Posts', Posts.flush, Posts),
        ('PostDataCache', PostDataCache.flush, PostDataCache),
        ('Reputations', Reputations.flush, Reputations),
        ('Votes', Votes.flush, Votes),
        ('Follow', Follow.flush, Follow),
        ('Reblog', Reblog.flush, Reblog),
        ('Notify', Notify.flush, Notify),
        ('Accounts', Accounts.flush, Accounts),
    ]

    def __init__(self):
        head_date = self.head_date()
        if head_date == '':
            self.__class__._head_block_date = None
            self.__class__._current_block_date = None
        else:
            self.__class__._head_block_date = head_date
            self.__class__._current_block_date = head_date

    @staticmethod
    def setup_own_db_access(shared_db_adapter: Db) -> None:
        PostDataCache.setup_own_db_access(shared_db_adapter, "PostDataCache")
        Reputations.setup_own_db_access(shared_db_adapter, "Reputations")
        Votes.setup_own_db_access(shared_db_adapter, "Votes")
        Follow.setup_own_db_access(shared_db_adapter, "Follow")
        Posts.setup_own_db_access(shared_db_adapter, "Posts")
        Reblog.setup_own_db_access(shared_db_adapter, "Reblog")
        Notify.setup_own_db_access(shared_db_adapter, "Notify")
        Accounts.setup_own_db_access(shared_db_adapter, "Accounts")
        PayoutStats.setup_own_db_access(shared_db_adapter, "PayoutStats")
        Mentions.setup_own_db_access(shared_db_adapter, "Mentions")

    @staticmethod
    def close_own_db_access() -> None:
        PostDataCache.close_own_db_access()
        Reputations.close_own_db_access()
        Votes.close_own_db_access()
        Follow.close_own_db_access()
        Posts.close_own_db_access()
        Reblog.close_own_db_access()
        Notify.close_own_db_access()
        Accounts.close_own_db_access()
        PayoutStats.close_own_db_access()
        Mentions.close_own_db_access()

    @staticmethod
    def head_num() -> int:
        """Get hive's head block number."""
        sql = "SELECT num FROM hive_blocks ORDER BY num DESC LIMIT 1"
        return DB.query_one(sql) or 0

    @staticmethod
    def head_date() -> str:
        """Get hive's head block date."""
        sql = "SELECT head_block_time()"
        return str(DB.query_one(sql) or '')

    @classmethod
    def set_end_of_sync_lib(cls, lib: int) -> None:
        """Set last block that guarantees cashout before end of sync based on LIB"""
        if lib < 10629455:
            # posts created before HF17 could stay unpaid forever
            cls._last_safe_cashout_block = 0
        else:
            # after HF17 all posts are paid after 7 days which means it is safe to assume that
            # posts created at or before LIB - 7days will be paidout at the end of massive sync
            cls._last_safe_cashout_block = lib - 7 * 24 * 1200
        log.info(
            "End-of-sync LIB is set to %d, last block that guarantees cashout at end of sync is %d",
            lib,
            cls._last_safe_cashout_block,
        )

    @classmethod
    def flush_data_in_n_threads(cls) -> None:
        completed_threads = 0

        pool = ThreadPoolExecutor(max_workers=len(cls._concurrent_flush))
        flush_futures = {
            pool.submit(time_collector, f): (description, c) for (description, f, c) in cls._concurrent_flush
        }
        for future in concurrent.futures.as_completed(flush_futures):
            (description, c) = flush_futures[future]
            completed_threads = completed_threads + 1
            try:
                (n, elapsedTime) = future.result()
                assert n is not None
                assert not c.sync_tx_active()

                FSM.flush_stat(description, elapsedTime, n)

            #                if n > 0:
            #                    log.info('%r flush generated %d records' % (description, n))
            except Exception as exc:
                log.error(f'{description!r} generated an exception: {exc}')
                raise exc
        pool.shutdown()

        assert completed_threads == len(cls._concurrent_flush)

    @classmethod
    def flush_data_in_1_thread(cls) -> None:
        for description, f, c in cls._concurrent_flush:
            try:
                f()
            except Exception as exc:
                log.error(f'{description!r} generated an exception: {exc}')
                raise exc

    @classmethod
    def process_blocks(cls, blocks) -> Tuple[int, int]:
        last_num = 0
        first_block = -1
        try:
            for block in blocks:
                if first_block == -1:
                    first_block = block.get_num()
                last_num = cls._process(block)
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
        register_time(flush_time, "Blocks", cls._flush_blocks())
        return first_block, last_num

    @classmethod
    def process_multi(cls, blocks, is_initial_sync: bool) -> None:
        """Batch-process blocks; wrapped in a transaction."""

        time_start = OPSM.start()

        DB.query("START TRANSACTION")

        first_block, last_num = cls.process_blocks(blocks)

        if not is_initial_sync:
            log.info("[PROCESS MULTI] Flushing data in 1 thread")
            cls.flush_data_in_1_thread()
            if first_block > -1:
                log.info("[PROCESS MULTI] Tables updating in live synchronization")
                cls.on_live_blocks_processed(first_block, last_num)

        DB.query("COMMIT")

        if is_initial_sync:
            log.info("[PROCESS MULTI] Flushing data in N threads")
            cls.flush_data_in_n_threads()

        log.info(f"[PROCESS MULTI] {len(blocks)} blocks in {OPSM.stop(time_start) :.4f}s")

    @staticmethod
    def prepare_vops(comment_payout_ops: dict, block: Block, date, block_num: int, is_safe_cashout: bool) -> dict:
        def get_empty_ops():
            return {
                VirtualOperationType.AUTHOR_REWARD: None,
                VirtualOperationType.COMMENT_REWARD: None,
                VirtualOperationType.EFFECTIVE_COMMENT_VOTE: None,
                VirtualOperationType.COMMENT_PAYOUT_UPDATE: None,
            }

        ineffective_deleted_ops = {}

        for vop in block.get_next_vop():
            start = OPSM.start()

            op_type = vop.get_type()
            assert op_type

            op_value = vop.get_body()
            op_value['block_num'] = block_num

            key = f"{op_value['author']}/{op_value['permlink']}"

            if op_type == VirtualOperationType.AUTHOR_REWARD:
                if key not in comment_payout_ops:
                    comment_payout_ops[key] = get_empty_ops()

                comment_payout_ops[key][op_type] = (op_value, date)

            elif op_type == VirtualOperationType.COMMENT_REWARD:
                if key not in comment_payout_ops:
                    comment_payout_ops[key] = get_empty_ops()

                comment_payout_ops[key][VirtualOperationType.EFFECTIVE_COMMENT_VOTE] = None

                comment_payout_ops[key][op_type] = (op_value, date)

            elif op_type == VirtualOperationType.EFFECTIVE_COMMENT_VOTE:
                Reputations.process_vote(block_num, op_value)
                # ABW: votes cast before HF1 (block 905693, timestamp 2016-04-25T17:30:00) have to be upscaled
                # by 1mln - there is no need to scale it anywhere else because first payouts happened only after
                # HF7; such scaling fixes some discrepancies in vote data of posts created before HF1
                # (we don't touch reputation - yet - because it affects a lot of test patterns)
                if block_num < 905693:
                    op_value["rshares"] *= 1000000
                Votes.effective_comment_vote_op(op_value)

                # skip effective votes for those posts that will become paidout before massive sync ends (both
                # total_vote_weight and pending_payout carried by this vop become zero when post is paid) - note
                # that the earliest we can use that is HF17 (block 10629455) which set cashout time to fixed 7 days
                if not is_safe_cashout:
                    if key not in comment_payout_ops:
                        comment_payout_ops[key] = get_empty_ops()

                    comment_payout_ops[key][op_type] = (op_value, date)

            elif op_type == VirtualOperationType.COMMENT_PAYOUT_UPDATE:
                if key not in comment_payout_ops:
                    comment_payout_ops[key] = get_empty_ops()

                comment_payout_ops[key][op_type] = (op_value, date)

            elif op_type == VirtualOperationType.INEFFECTIVE_DELETE_COMMENT:
                ineffective_deleted_ops[key] = {}

            OPSM.op_stats(str(op_type), OPSM.stop(start))

        return ineffective_deleted_ops

    @classmethod
    def _process(cls, block: Block) -> int:
        """Process a single block. Assumes a trx is open."""
        # pylint: disable=too-many-branches
        assert issubclass(type(block), Block)
        num = cls._push(block)
        cls._current_block_date = block.get_date()

        # head block date shall point to last imported block (not yet current one) to conform hived behavior.
        # that's why operations processed by node are included in the block being currently produced, so its processing time is equal to last produced block.
        # unfortunately it is not true to all operations, most likely in case of dates that used to come from
        # FatNode where it supplemented it with its-current head block, since it was already past block processing,
        # it saw later block (equal to _current_block_date here)
        if cls._head_block_date is None:
            cls._head_block_date = cls._current_block_date

        ineffective_deleted_ops = Blocks.prepare_vops(
            Posts.comment_payout_ops, block, cls._current_block_date, num, num <= cls._last_safe_cashout_block
        )

        json_ops = []
        for transaction in block.get_next_transaction():
            assert issubclass(type(transaction), Transaction)
            for operation in transaction.get_next_operation():
                assert issubclass(type(operation), Operation)

                start = OPSM.start()
                op_type = operation.get_type()
                assert op_type, "Only supported types are expected"
                op = operation.get_body()

                assert 'block_num' not in op
                op['block_num'] = num

                account_name = None
                op_details = None
                potentially_new_account = False
                # account ops
                if op_type == OperationType.POW:
                    account_name = op['worker_account']
                    potentially_new_account = True
                elif op_type == OperationType.POW_2:
                    account_name = op['work']['value']['input']['worker_account']
                    potentially_new_account = True
                elif op_type == OperationType.ACCOUNT_CREATE:
                    account_name = op['new_account_name']
                    op_details = op
                    potentially_new_account = True
                elif op_type == OperationType.ACCOUNT_CREATE_WITH_DELEGATION:
                    account_name = op['new_account_name']
                    op_details = op
                    potentially_new_account = True
                elif op_type == OperationType.CREATE_CLAIMED_ACCOUNT:
                    account_name = op['new_account_name']
                    op_details = op
                    potentially_new_account = True

                if potentially_new_account and not Accounts.register(
                    account_name, op_details, cls._head_block_date, num
                ):
                    log.error(f"Failed to register account {account_name} from operation: {op}")

                # account metadata updates
                if op_type == OperationType.ACCOUNT_UPDATE:
                    Accounts.update_op(op, False)
                elif op_type == OperationType.ACCOUNT_UPDATE_2:
                    Accounts.update_op(op, True)

                # post ops
                elif op_type == OperationType.COMMENT:
                    Posts.comment_op(op, cls._head_block_date)
                elif op_type == OperationType.DELETE_COMMENT:
                    key = f"{op['author']}/{op['permlink']}"
                    if key not in ineffective_deleted_ops:
                        Posts.delete_op(op, cls._head_block_date)
                elif op_type == OperationType.COMMENT_OPTION:
                    Posts.comment_options_op(op)
                elif op_type == OperationType.VOTE:
                    Votes.vote_op(op, cls._head_block_date)

                # misc ops
                elif op_type == OperationType.TRANSFER:
                    Payments.op_transfer(op, transaction.get_id(), num, cls._head_block_date)
                elif op_type == OperationType.CUSTOM_JSON:  # follow/reblog/community ops
                    CustomOp.process_op(op, num, cls._head_block_date)

                OPSM.op_stats(str(op_type), OPSM.stop(start))

        cls._head_block_date = cls._current_block_date

        return num

    @classmethod
    def verify_head(cls, steem: SteemClient) -> None:
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
            log.info(
                "[INIT] fork check. block %d: %s vs %s --- %s",
                hive_block['num'],
                hive_block['hash'],
                steem_hash,
                'ok' if match else 'invalid',
            )
            if match:
                break
            to_pop.append(hive_block)
            cursor -= 1

        if hive_head == cursor:
            return  # no fork!

        log.error("[FORK] depth is %d; popping blocks %d - %d", hive_head - cursor, cursor + 1, hive_head)

        # we should not attempt to recover from fork until it's safe
        fork_limit = steem.last_irreversible()
        assert cursor < fork_limit, "not proceeding until head is irreversible"

        cls._pop(to_pop)

    @staticmethod
    def _get(num: int) -> dict:
        """Fetch a specific block."""
        sql = "SELECT num, created_at date, hash FROM hive_blocks WHERE num = :num LIMIT 1"
        return dict(DB.query_row(sql, num=num))

    @classmethod
    def _push(cls, block: Block) -> int:
        """Insert a row in `hive_blocks`."""
        cls.blocks_to_flush.append(
            {
                'num': block.get_num(),
                'hash': block.get_hash(),
                'prev': block.get_previous_block_hash(),
                'txs': block.get_number_of_transactions(),
                'ops': block.get_number_of_operations(),
                'date': block.get_date(),
            }
        )
        return block.get_num()

    @classmethod
    def _flush_blocks(cls) -> int:
        query = "INSERT INTO hive_blocks (num, hash, prev, txs, ops, created_at, completed) VALUES"
        values = []
        for block in cls.blocks_to_flush:
            values.append(
                f"({block['num']}, '{block['hash']}', '{block['prev']}', {block['txs']}, {block['ops']}, '{block['date']}', {False})"
            )
        query = query + ",".join(values)
        DB.query_prepared(query)
        values.clear()
        n = len(cls.blocks_to_flush)
        cls.blocks_to_flush.clear()
        return n

    @classmethod
    def _pop(cls, blocks) -> None:
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
                DB.query("DELETE FROM hive_posts       WHERE id      IN :ids", ids=post_ids)
                DB.query("DELETE FROM hive_post_data   WHERE id      IN :ids", ids=post_ids)

            DB.query("DELETE FROM hive_payments    WHERE block_num = :num", num=num)
            DB.query("DELETE FROM hive_blocks      WHERE num = :num", num=num)

        DB.query("COMMIT")
        log.warning("[FORK] recovery complete")
        # TODO: manually re-process here the blocks which were just popped.

    @staticmethod
    @time_it
    def on_live_blocks_processed(lbound: int, ubound: int) -> None:
        """Is invoked when processing of block range is done and received
        informations from hived are already stored in db
        """
        is_hour_action = ubound % 1200 == 0

        queries = [
            f"SELECT update_posts_rshares({lbound}, {ubound})",
            f"SELECT update_hive_posts_children_count({lbound}, {ubound})",
            f"SELECT update_hive_posts_root_id({lbound},{ubound})",
            f"SELECT update_hive_posts_api_helper({lbound},{ubound})",
            f"SELECT update_feed_cache({lbound}, {ubound})",
            f"SELECT update_hive_posts_mentions({lbound}, {ubound})",
            f"SELECT update_notification_cache({lbound}, {ubound}, {is_hour_action})",
            f"SELECT update_follow_count({lbound}, {ubound})",
            f"SELECT update_account_reputations({lbound}, {ubound}, False)",
            f"SELECT update_hive_blocks_consistency_flag({lbound}, {ubound})",
        ]

        for query in queries:
            time_start = perf_counter()
            DB.query_no_return(query)
            log.info("%s executed in: %.4f s", query, perf_counter() - time_start)

    @staticmethod
    def is_consistency() -> bool:
        """Check if all tuples in `hive_blocks` are written correctly.
        If any record has `completed` == false, it indicates that the database was closed incorrectly or a rollback failed.
        """
        not_completed_blocks = DB.query_one("SELECT count(*) FROM hive_blocks WHERE completed = false LIMIT 1")
        log.info("[INIT] Number of not completed blocks: %s.", not_completed_blocks)
        return not_completed_blocks == 0
