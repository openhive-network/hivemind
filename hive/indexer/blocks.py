"""Blocks processor."""

import concurrent
from concurrent.futures import ThreadPoolExecutor
import logging
from pathlib import Path
from time import perf_counter
from typing import Tuple

from hive.conf import Conf, SCHEMA_NAME
from hive.db.adapter import Db
from hive.indexer.accounts import Accounts
from hive.indexer.block import Block, Operation, OperationType, Transaction, VirtualOperationType
from hive.indexer.custom_op import CustomOp
from hive.indexer.follow import Follow
from hive.indexer.hive_db.block import BlockHiveDb
from hive.indexer.notify import Notify
from hive.indexer.payments import Payments
from hive.indexer.post_data_cache import PostDataCache
from hive.indexer.posts import Posts
from hive.indexer.reblog import Reblog
from hive.indexer.reputations import Reputations
from hive.indexer.votes import Votes
from hive.server.common.mentions import Mentions
from hive.server.common.payout_stats import PayoutStats
from hive.utils.communities_rank import update_communities_posts_and_rank
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
    """Processes blocks, dispatches work, manages the state of the database (blocks consistency, and numbers)."""

    _conf = None
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

    @classmethod
    def setup(cls, conf: Conf):
        cls._conf = conf

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
        """Get head block number from the application view (hive.hivemind_app_blocks_view)."""
        sql = f"SELECT num FROM {SCHEMA_NAME}.get_head_state();"
        return DB.query_one(sql) or 0

    @staticmethod
    def last_imported() -> int:
        """
        Get hivemind_app last block that was imported.
        (could not be completed yet! which means there were no update queries run with this block number)
        """
        sql = f"SELECT last_imported_block_num FROM {SCHEMA_NAME}.hive_state;"
        return DB.query_one(sql) or 0

    @staticmethod
    def last_completed() -> int:
        """
        Get hivemind_app last block that was completed.
        (block is considered as completed when all update queries were run with this block number)
        """
        sql = f"SELECT hive.app_get_current_block_num('{SCHEMA_NAME}');"
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
        last_date = None
        first_block = -1
        try:
            for block in blocks:
                if first_block == -1:
                    first_block = block.get_num()
                last_num = cls._process(block)
                last_date = block.get_date()
        except Exception as e:
            log.error("exception encountered block %d", last_num + 1)
            raise e

        # Follows flushing needs to be atomic because recounts are
        # expensive. So is tracking follows at all; hence we track
        # deltas in memory and update follow/er counts in bulk.

        log.info("#############################################################################")
        sql = f'SELECT {SCHEMA_NAME}.update_last_imported_block(:last_num, :last_date);'
        DB.query_no_return(sql, last_num=last_num, last_date=last_date)
        return first_block, last_num

    @classmethod
    def process_multi(cls, blocks, is_massive_sync: bool) -> None:
        """Batch-process blocks; wrapped in a transaction."""

        time_start = OPSM.start()

        if is_massive_sync:
            DB.query("START TRANSACTION")
            #update last_active_at directly since we don't advance current_block_num in massive_sync (until whole indexer gets re-write)
            DB.query_no_return(f"SELECT hive.app_update_last_active_at('hivemind_app');");

        first_block, last_num = cls.process_blocks(blocks)

        if not is_massive_sync:
            log.info("[PROCESS MULTI] Flushing data in 1 thread")
            cls.flush_data_in_1_thread()
            if first_block > -1:
                log.info("[PROCESS MULTI] Tables updating in live synchronization")
                cls.on_live_blocks_processed(first_block)
                cls._periodic_actions(blocks[0])

        DB.query("COMMIT")

        if is_massive_sync:
            log.info("[PROCESS MULTI] Flushing data in N threads")
            cls.flush_data_in_n_threads()

        log.info(f"[PROCESS MULTI] {len(blocks)} blocks in {OPSM.stop(time_start) :.4f}s")

    @classmethod
    def _periodic_actions(cls, block: BlockHiveDb) -> None:
        """Actions performed at a given time, calculated on the basis of the current block number"""

        if (block_num := block.get_num()) % 1200 == 0:  # 1hour
            log.info(f"head block {block_num} @ {block.get_date()}")
            log.info("[SINGLE] hourly stats")
            log.info("[SINGLE] filling payout_stats_view executed")
            PayoutStats.generate()
            Mentions.refresh()
        elif block_num % 200 == 0:  # 10min
            log.info("[SINGLE] 10min")
            log.info("[SINGLE] updating communities posts and rank")
            update_communities_posts_and_rank(db=DB)

    @classmethod
    def prepare_vops(cls, comment_payout_ops: dict, block: Block, date, block_num: int, is_safe_cashout: bool) -> dict:
        def get_empty_ops():
            return {
                VirtualOperationType.AUTHOR_REWARD: None,
                VirtualOperationType.COMMENT_REWARD: None,
                VirtualOperationType.EFFECTIVE_COMMENT_VOTE: None,
                VirtualOperationType.COMMENT_PAYOUT_UPDATE: None,
            }

        ineffective_deleted_ops = {}

        for vop in block.get_next_vop():
            if cls._conf.get('log_virtual_op_calls'):
                with open(Path(__file__).parent.parent / 'virtual_operations.log', 'a', encoding='utf-8') as file:
                    file.write(f'{block.get_num()}: {vop.get_type()}')
                    file.write(str(vop.get_body()))

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
        num = block.get_num()
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

                if cls._conf.get('log_op_calls'):
                    with open(Path(__file__).parent.parent / 'operations.log', 'a', encoding='utf-8') as file:
                        file.write(f'{block.get_num()}: {operation.get_type()}')
                        file.write(str(operation.get_body()))

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

    @staticmethod
    @time_it
    def on_live_blocks_processed(block_number: int) -> None:
        """Is invoked when processing of block range is done and received
        informations from hived are already stored in db
        """
        is_hour_action = block_number % 1200 == 0

        queries = [
            f"SELECT {SCHEMA_NAME}.update_posts_rshares({block_number}, {block_number})",
            f"SELECT {SCHEMA_NAME}.update_hive_posts_children_count({block_number}, {block_number})",
            f"SELECT {SCHEMA_NAME}.update_hive_posts_root_id({block_number},{block_number})",
            f"SELECT {SCHEMA_NAME}.update_hive_posts_api_helper({block_number},{block_number})",
            f"SELECT {SCHEMA_NAME}.update_feed_cache({block_number}, {block_number})",
            f"SELECT {SCHEMA_NAME}.update_hive_posts_mentions({block_number}, {block_number})",
            f"SELECT {SCHEMA_NAME}.update_notification_cache({block_number}, {block_number}, {is_hour_action})",
            f"SELECT {SCHEMA_NAME}.update_follow_count({block_number}, {block_number})",
            f"SELECT {SCHEMA_NAME}.update_account_reputations({block_number}, {block_number}, False)",
            f"SELECT hive.app_set_current_block_num('{SCHEMA_NAME}', {block_number})",
        ]

        for query in queries:
            time_start = perf_counter()
            DB.query_no_return(query)
            log.info("%s executed in: %.4f s", query, perf_counter() - time_start)

    @staticmethod
    def is_consistency() -> bool:
        """
        Check if all tuples in are written correctly.
        If there are any not_completed_blocks, it means that there were no update queries ran on these blocks.
        """
        not_completed_blocks = Blocks.last_imported() - Blocks.last_completed()

        if not_completed_blocks:
            log.warning(f"Number of not completed blocks: {not_completed_blocks}")
            return False
        return True
