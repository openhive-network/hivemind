"""Blocks processor."""

import concurrent
from concurrent.futures import ThreadPoolExecutor
import logging
from pathlib import Path
from time import perf_counter
from typing import Tuple

from hive.conf import Conf, SCHEMA_NAME, ONE_WEEK_IN_BLOCKS
from hive.db.adapter import Db
from hive.db.db_state import DbState
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.indexer.hive_db.massive_blocks_data_provider import MassiveBlocksDataProviderHiveDb
from hive.indexer.accounts import Accounts
from hive.indexer.block import Block, Operation, OperationType, Transaction, VirtualOperationType
from hive.indexer.custom_op import CustomOp
from hive.indexer.follow import Follow
from hive.indexer.hive_db.block import BlockHiveDb
from hive.indexer.notify import Notify
from hive.indexer.post_data_cache import PostDataCache
from hive.indexer.posts import Posts
from hive.indexer.reblog import Reblog
from hive.indexer.votes import Votes
from hive.indexer.mentions import Mentions
from hive.indexer.notification_cache import (
    NotificationCache,
    VoteNotificationCache,
    PostNotificationCache,
    FollowNotificationCache,
    ReblogNotificationCache
)
from hive.utils.payout_stats import PayoutStats
from hive.utils.communities_rank import update_communities_posts_and_rank
from hive.utils.stats import FlushStatusManager as FSM
from hive.utils.stats import OPStatusManager as OPSM
from hive.utils.timer import time_it
from hive.indexer.flusher import time_collector, process_flush_items, process_flush_items_threaded

log = logging.getLogger(__name__)


class Blocks:
    """Processes blocks, dispatches work, manages the state of the database (blocks consistency, and numbers)."""

    _conf = None
    _head_block_date = None
    _current_block_date = None
    _last_safe_cashout_block = 0
    _is_initial_sync = False

    @classmethod
    def setup(cls, conf: Conf):
        cls._conf = conf

    @classmethod
    def set_head_date(cls):
        head_date = cls.head_date()
        if head_date == '':
            cls._head_block_date = None
            cls._current_block_date = None
        else:
            cls._head_block_date = head_date
            cls._current_block_date = head_date

    @staticmethod
    def setup_own_db_access(shared_db_adapter: Db) -> None:
        if DbState.is_massive_sync():
            DbAdapterHolder.open_common_blocks_in_background_processing_db()

        PostDataCache.setup_own_db_access(shared_db_adapter, "PostDataCache")
        Votes.setup_own_db_access(shared_db_adapter, "Votes")
        Follow.setup_own_db_access(shared_db_adapter, "Follow")
        Posts.setup_own_db_access(shared_db_adapter, "Posts")
        Reblog.setup_own_db_access(shared_db_adapter, "Reblog")
        Notify.setup_own_db_access(shared_db_adapter, "Notify")
        Accounts.setup_own_db_access(shared_db_adapter, "Accounts")
        Mentions.setup_own_db_access(shared_db_adapter, "Mentions")
        NotificationCache.setup_own_db_access(shared_db_adapter, "NotificationCache")
        VoteNotificationCache.setup_own_db_access(shared_db_adapter, "VoteNotificationCache")
        PostNotificationCache.setup_own_db_access(shared_db_adapter, "PostNotificationCache")
        FollowNotificationCache.setup_own_db_access(shared_db_adapter, "FollowNotificationCache")
        ReblogNotificationCache.setup_own_db_access(shared_db_adapter, "ReblogNotificationCache")

    @staticmethod
    def close_own_db_access() -> None:
        DbAdapterHolder.close_common_blocks_in_background_processing_db()

        PostDataCache.close_own_db_access()
        Votes.close_own_db_access()
        Follow.close_own_db_access()
        Posts.close_own_db_access()
        Reblog.close_own_db_access()
        Notify.close_own_db_access()
        Accounts.close_own_db_access()
        Mentions.close_own_db_access()
        NotificationCache.close_own_db_access()
        VoteNotificationCache.close_own_db_access()
        PostNotificationCache.close_own_db_access()
        FollowNotificationCache.close_own_db_access()
        ReblogNotificationCache.close_own_db_access()

    @staticmethod
    def head_num() -> int:
        """Get head block number from the application view (hive.hivemind_app_blocks_view)."""
        sql = f"SELECT num FROM {SCHEMA_NAME}.get_head_state();"
        return Db.instance().query_one(sql) or 0

    @staticmethod
    def last_imported() -> int:
        """
        Get hivemind_app last block that was imported.
        (could not be completed yet! which means there were no update queries run with this block number)
        """
        sql = f"SELECT hive.app_get_current_block_num( '{SCHEMA_NAME}' )"
        return Db.instance().query_one(sql) or 0

    @staticmethod
    def last_completed() -> int:
        """
        Get hivemind_app last block that was completed.
        (block is considered as completed when all update queries were run with this block number)
        """
        sql = f"SELECT last_completed_block_num FROM {SCHEMA_NAME}.hive_state;"
        return Db.instance().query_one(sql) or 0

    @staticmethod
    def head_date() -> str:
        """Get hive's head block date."""
        sql = f"SELECT {SCHEMA_NAME}.head_block_time()"
        return str(Db.instance().query_one(sql) or '')

    @classmethod
    def set_end_of_sync_lib(cls) -> None:
        sql = f"SELECT hive.app_get_irreversible_block( '{SCHEMA_NAME}' )"
        lib = Db.instance().query_one(sql)
        """Set last block that guarantees cashout before end of sync based on LIB"""
        if lib < 10629455:
            # posts created before HF17 could stay unpaid forever
            cls._last_safe_cashout_block = 0
        else:
            # after HF17 all posts are paid after 7 days which means it is safe to assume that
            # posts created at or before LIB - 7days will be paidout at the end of massive sync
            cls._last_safe_cashout_block = lib - ONE_WEEK_IN_BLOCKS
        log.info(
            "End-of-sync LIB is set to %d, last block that guarantees cashout at end of sync is %d",
            lib,
            cls._last_safe_cashout_block,
        )

    @classmethod
    def is_before_first_not_pruned_block(cls) -> bool:
        if not cls._conf.is_pruning():
            return False

        pruning_days = str( cls._conf.get_prune_days() )
        sql = f"SELECT hivemind_app.is_far_than_interval( '{pruning_days} days' )"
        res = Db.instance().query_one(sql)
        return res

    @classmethod
    def update_flushers(cls):
        if not cls.is_before_first_not_pruned_block():
            cls._concurrent_flush_1 = [
                ('Posts', Posts.flush, Posts),
                ('PostDataCache', PostDataCache.flush, PostDataCache),
                ('Votes', Votes.flush, Votes),
                ('Follow', Follow.flush, Follow),
                ('Reblog', Reblog.flush, Reblog),
                ('Notify', Notify.flush, Notify),
            ]
            cls._concurrent_flush_2 = [
                ('Accounts', Accounts.flush, Accounts),
                ("VoteNotifications", VoteNotificationCache.flush_vote_notifications, VoteNotificationCache),
                ("PostNotifications", PostNotificationCache.flush_post_notifications, PostNotificationCache),
                ("FollowNotifications", FollowNotificationCache.flush_follow_notifications, FollowNotificationCache),
                ("ReblogNotifications", ReblogNotificationCache.flush_reblog_notifications, ReblogNotificationCache),
            ]
        else:
            cls._concurrent_flush_1 = [
                ('Follow', Follow.flush, Follow),
                ('Reblog', Reblog.flush, Reblog),
            ]
            cls._concurrent_flush_2 = [
                ('Accounts', Accounts.flush, Accounts),
            ]
    @classmethod
    def flush_data_in_n_threads(cls) -> None:
        cls.update_flushers()
        process_flush_items_threaded(cls._concurrent_flush_1)
        process_flush_items_threaded(cls._concurrent_flush_2)

    @classmethod
    def flush_data_in_1_thread(cls) -> None:
        cls.update_flushers()
        process_flush_items(cls._concurrent_flush_1)
        process_flush_items(cls._concurrent_flush_2)

    @classmethod
    def process_blocks(cls, blocks) -> Tuple[int, int]:
        last_num = 0
        first_block = -1
        try:
            for block_raw in blocks:
                hiveBlock = BlockHiveDb(
                    block_raw,
                    MassiveBlocksDataProviderHiveDb._operation_id_to_enum
                )
                if first_block == -1:
                    first_block = hiveBlock.get_num()
                last_num = cls._process(hiveBlock)
        except Exception as e:
            log.error("exception encountered block %d", last_num + 1)
            raise e
        # Follows flushing needs to be atomic because recounts are
        # expensive. So is tracking follows at all; hence we track
        # deltas in memory and update follow/er counts in bulk.

        log.info("#############################################################################")
        return first_block, last_num

    @classmethod
    def process_multi(cls, blocks, is_massive_sync: bool) -> None:
        """Batch-process blocks; wrapped in a transaction."""
        time_start = OPSM.start()

        if is_massive_sync:
            DbAdapterHolder.common_block_processing_db().query_no_return("START TRANSACTION")

        first_block, last_num = cls.process_blocks(blocks)

        if is_massive_sync:
            DbAdapterHolder.common_block_processing_db().query_no_return("COMMIT")

        if not is_massive_sync:
            log.info("[PROCESS MULTI] Flushing data in 1 thread")
            cls.flush_data_in_1_thread()
            if first_block > -1:
                log.info("[PROCESS MULTI] Tables updating in live synchronization")
                cls.on_live_blocks_processed(first_block)
                cls._periodic_actions(blocks[0])

        if is_massive_sync:
            log.info("[PROCESS MULTI] Flushing data in N threads")
            cls.flush_data_in_n_threads()

        log.info(f"[PROCESS MULTI] {len(blocks)} blocks in {OPSM.stop(time_start) :.4f}s")

    @classmethod
    def _periodic_actions(cls, block_raw) -> None:
        """Actions performed at a given time, calculated on the basis of the current block number"""
        block = BlockHiveDb(
            block_raw,
            MassiveBlocksDataProviderHiveDb._operation_id_to_enum
        )

        if (block_num := block.get_num()) % 1200 == 0:  # 1hour
            log.info(f"head block {block_num} @ {block.get_date()}")
            log.info("[SINGLE] hourly stats")
            log.info("[SINGLE] filling payout_stats_view executed")
            PayoutStats.generate(db=DbAdapterHolder.common_block_processing_db())
            Mentions.refresh()
        elif block_num % 200 == 0:  # 10min
            log.info("[SINGLE] 10min")
            log.info("[SINGLE] updating communities posts and rank")
            update_communities_posts_and_rank(db=DbAdapterHolder.common_block_processing_db())

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

        def try_register_account(account_name, op, op_details):
            if not Accounts.register(
                account_name, op_details, cls._head_block_date, num
            ):
                log.error(f"Failed to register account {account_name} from operation: {op}")

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

                # account ops
                if op_type == OperationType.POW:
                    try_register_account(op['worker_account'], op, None)
                elif op_type == OperationType.POW_2:
                    try_register_account(op['work']['value']['input']['worker_account'], op, None)
                elif op_type == OperationType.ACCOUNT_CREATE:
                    try_register_account(op['new_account_name'], op, op)
                elif op_type == OperationType.ACCOUNT_CREATE_WITH_DELEGATION:
                    try_register_account(op['new_account_name'], op, op)
                elif op_type == OperationType.CREATE_CLAIMED_ACCOUNT:
                    try_register_account(op['new_account_name'], op, op)

                # account metadata updates
                elif op_type == OperationType.ACCOUNT_UPDATE:
                    Accounts.update_op(op, False)
                elif op_type == OperationType.ACCOUNT_UPDATE_2:
                    Accounts.update_op(op, True)

                # post ops
                elif op_type == OperationType.COMMENT:
                    if not cls.is_before_first_not_pruned_block():
                        Posts.comment_op(op, cls._head_block_date)
                elif op_type == OperationType.DELETE_COMMENT:
                    if not cls.is_before_first_not_pruned_block():
                        key = f"{op['author']}/{op['permlink']}"
                        Posts.delete_op(op, cls._head_block_date)
                elif op_type == OperationType.COMMENT_OPTION:
                    if not cls.is_before_first_not_pruned_block():
                        Posts.comment_options_op(op)
                elif op_type == OperationType.VOTE:
                    if not cls.is_before_first_not_pruned_block():
                        Votes.vote_op(op, cls._head_block_date)

                # misc ops
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
        queries = [
            f"SELECT {SCHEMA_NAME}.update_hive_posts_children_count({block_number}, {block_number})",
            f"SELECT {SCHEMA_NAME}.update_hive_posts_root_id({block_number},{block_number})",
            f"SELECT {SCHEMA_NAME}.update_feed_cache({block_number}, {block_number})",
            f"SELECT {SCHEMA_NAME}.update_last_completed_block({block_number})",
            f"SELECT {SCHEMA_NAME}.prune_notification_cache({block_number})",
        ]

        for query in queries:
            time_start = perf_counter()
            DbAdapterHolder.common_block_processing_db().query_no_return(query)
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
