"""Blocks processor."""

import logging
from pathlib import Path
from time import perf_counter

from sqlalchemy import text

from hive.conf import ONE_WEEK_IN_BLOCKS, SCHEMA_NAME, Conf
from hive.db.adapter import Db
from hive.db.db_state import DbState
from hive.indexer.accounts import Accounts
from hive.indexer.block import Block, Operation, OperationType, Transaction, VirtualOperationType
from hive.indexer.custom_op import CustomOp
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.indexer.flusher import process_flush_items, process_flush_items_threaded
from hive.indexer.follow import Follow
from hive.indexer.hive_db.block import BlockHiveDb
from hive.indexer.hive_db.massive_blocks_data_provider import MassiveBlocksDataProviderHiveDb
from hive.indexer.mentions import Mentions
from hive.indexer.notification_cache import (
    FollowNotificationCache,
    NotificationCache,
    PostNotificationCache,
    ReblogNotificationCache,
    VoteNotificationCache,
)
from hive.indexer.notify import Notify
from hive.indexer.post_data_cache import PostDataCache
from hive.indexer.posts import Posts
from hive.indexer.reblog import Reblog
from hive.indexer.votes import Votes
from hive.utils.communities_rank import update_communities_posts_and_rank
from hive.utils.normalize import escape_characters
from hive.utils.payout_stats import PayoutStats
from hive.utils.stats import OPStatusManager as OPSM
from hive.utils.timer import time_it

log = logging.getLogger(__name__)


class Blocks:
    """Processes blocks, dispatches work, manages the state of the database (blocks consistency, and numbers)."""

    _conf = None
    _head_block_date = None
    _current_block_date = None
    _last_safe_cashout_block = 0
    _is_initial_sync = False

    _concurrent_flush_1 = [
        ('Posts', Posts.flush, Posts),
        ('PostDataCache', PostDataCache.flush, PostDataCache),
        ('Votes', Votes.flush, Votes),
        ('Follow', Follow.flush, Follow),
        ('Reblog', Reblog.flush, Reblog),
        ('Notify', Notify.flush, Notify),
    ]
    _concurrent_flush_2 = [
        ('Accounts', Accounts.flush, Accounts),
        ("VoteNotifications", VoteNotificationCache.flush_vote_notifications, VoteNotificationCache),
        ("PostNotifications", PostNotificationCache.flush_post_notifications, PostNotificationCache),
        ("FollowNotifications", FollowNotificationCache.flush_follow_notifications, FollowNotificationCache),
        ("ReblogNotifications", ReblogNotificationCache.flush_reblog_notifications, ReblogNotificationCache),
    ]

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

    @classmethod
    def flush_data_in_n_threads(cls) -> None:
        process_flush_items_threaded(cls._concurrent_flush_1)
        process_flush_items_threaded(cls._concurrent_flush_2)

    @classmethod
    def flush_data_in_1_thread(cls) -> None:
        process_flush_items(cls._concurrent_flush_1)
        process_flush_items(cls._concurrent_flush_2)

    # Op type ID → OPSM stat name mapping (matches str(enum_value) for consistency)
    _OP_STAT_NAMES = {
        0: 'OperationType.VOTE',
        1: 'OperationType.COMMENT',
        9: 'OperationType.ACCOUNT_CREATE',
        10: 'OperationType.ACCOUNT_UPDATE',
        14: 'OperationType.POW',
        17: 'OperationType.DELETE_COMMENT',
        18: 'OperationType.CUSTOM_JSON',
        19: 'OperationType.COMMENT_OPTION',
        23: 'OperationType.CREATE_CLAIMED_ACCOUNT',
        30: 'OperationType.POW_2',
        41: 'OperationType.ACCOUNT_CREATE_WITH_DELEGATION',
        43: 'OperationType.ACCOUNT_UPDATE_2',
        51: 'VirtualOperationType.AUTHOR_REWARD',
        53: 'VirtualOperationType.COMMENT_REWARD',
        61: 'VirtualOperationType.COMMENT_PAYOUT_UPDATE',
        72: 'VirtualOperationType.EFFECTIVE_COMMENT_VOTE',
        73: 'VirtualOperationType.INEFFECTIVE_DELETE_COMMENT',
    }

    @classmethod
    def process_blocks(cls, blocks) -> tuple[int, int]:
        last_num = 0
        first_block = -1
        try:
            for block_raw in blocks:
                hiveBlock = BlockHiveDb(block_raw, MassiveBlocksDataProviderHiveDb._operation_id_to_enum)
                if first_block == -1:
                    first_block = hiveBlock.get_num()
                last_num = cls._process(hiveBlock)
        except Exception as e:
            log.error("exception encountered block %d", last_num + 1)
            raise e
        # Follows flushing needs to be atomic because recounts are
        # expensive. So is tracking follows at all; hence we track
        # deltas in memory and update follow/er counts in bulk.

        return first_block, last_num

    @classmethod
    def process_blocks_flat(cls, op_rows, block_dates: dict) -> tuple[int, int]:
        """Process flat operation rows for massive sync - no wrapper objects.

        op_rows: flat rows from get_ops_for_hivemind(), each with (block_num, op_type_id, body).
                 body is already a Python dict (psycopg2 jsonb→dict), the 'value' payload only.
                 Rows are sorted by operation ID (regular ops before virtual ops within each block).
        block_dates: dict of {block_num: date_string} from get_block_dates_for_hivemind().
        """
        if not block_dates:
            return -1, 0

        # Group operations by block_num, partitioned into virtual and regular
        block_vops = {}  # block_num -> [(op_type_id, body), ...]
        block_ops = {}  # block_num -> [(op_type_id, body), ...]

        for row in op_rows:
            row_m = row._mapping
            block_num = row_m['block_num']
            op_type_id = row_m['op_type_id']
            body = row_m['body']

            if op_type_id >= 50:
                if block_num not in block_vops:
                    block_vops[block_num] = []
                block_vops[block_num].append((op_type_id, body))
            else:
                if block_num not in block_ops:
                    block_ops[block_num] = []
                block_ops[block_num].append((op_type_id, body))

        sorted_blocks = sorted(block_dates.keys())
        first_block = sorted_blocks[0]
        last_num = first_block

        try:
            for block_num in sorted_blocks:
                date = block_dates[block_num]
                cls._current_block_date = date

                if cls._head_block_date is None:
                    cls._head_block_date = cls._current_block_date

                vops = block_vops.get(block_num)
                ops = block_ops.get(block_num)

                if vops or ops:
                    is_safe_cashout = block_num <= cls._last_safe_cashout_block
                    ineffective_deleted_ops = cls._process_vops_flat(
                        Posts.comment_payout_ops, vops or [], date, block_num, is_safe_cashout
                    )
                    if ops:
                        cls._process_ops_flat(ops, block_num, ineffective_deleted_ops)

                cls._head_block_date = cls._current_block_date
                last_num = block_num
        except Exception as e:
            log.error("exception encountered block %d", last_num + 1)
            raise e

        return first_block, last_num

    @classmethod
    def process_blocks_flat_extended(cls, op_rows, block_dates: dict) -> tuple[int, int]:
        """Like process_blocks_flat but for extended rows with extracted vote fields.

        op_rows: rows from get_ops_for_hivemind_v2(), each with (block_num, op_type_id, body,
                 f_voter, f_author, f_permlink, f_weight, f_rshares).
                 For vote (0) and effective_comment_vote (72) ops, body is NULL and the
                 f_* fields contain the extracted values. For all other ops, body is the
                 jsonb payload and f_* fields are NULL.
        """
        if not block_dates:
            return -1, 0

        block_vops = {}
        block_ops = {}

        for row in op_rows:
            row_m = row._mapping
            block_num = row_m['block_num']
            op_type_id = row_m['op_type_id']

            if op_type_id == 0:  # VOTE - build dict from extracted columns
                body = {
                    'voter': row_m['f_voter'],
                    'author': row_m['f_author'],
                    'permlink': row_m['f_permlink'],
                    'weight': row_m['f_weight'],
                }
            elif op_type_id == 72:  # EFFECTIVE_COMMENT_VOTE
                body = {
                    'voter': row_m['f_voter'],
                    'author': row_m['f_author'],
                    'permlink': row_m['f_permlink'],
                    'weight': row_m['f_weight'],
                    'rshares': row_m['f_rshares'],
                    'pending_payout': row_m['f_pending_payout'],
                    'total_vote_weight': row_m['f_total_vote_weight'],
                }
            else:
                body = row_m['body']

            if op_type_id >= 50:
                if block_num not in block_vops:
                    block_vops[block_num] = []
                block_vops[block_num].append((op_type_id, body))
            else:
                if block_num not in block_ops:
                    block_ops[block_num] = []
                block_ops[block_num].append((op_type_id, body))

        sorted_blocks = sorted(block_dates.keys())
        first_block = sorted_blocks[0]
        last_num = first_block

        try:
            for block_num in sorted_blocks:
                date = block_dates[block_num]
                cls._current_block_date = date

                if cls._head_block_date is None:
                    cls._head_block_date = cls._current_block_date

                vops = block_vops.get(block_num)
                ops = block_ops.get(block_num)

                if vops or ops:
                    is_safe_cashout = block_num <= cls._last_safe_cashout_block
                    ineffective_deleted_ops = cls._process_vops_flat(
                        Posts.comment_payout_ops, vops or [], date, block_num, is_safe_cashout
                    )
                    if ops:
                        cls._process_ops_flat(ops, block_num, ineffective_deleted_ops)

                cls._head_block_date = cls._current_block_date
                last_num = block_num
        except Exception as e:
            log.error("exception encountered block %d", last_num + 1)
            raise e

        return first_block, last_num

    @classmethod
    def process_blocks_combined_extended(cls, combined_rows) -> tuple[int, int, int]:
        """Process combined (ops + block dates) rows from single-query path with extended vote fields.

        combined_rows: rows from get_blocks_and_ops_for_hivemind_v2(), each with
                       (block_num, date, op_type_id, body, f_voter, f_author, f_permlink,
                        f_weight, f_rshares, f_pending_payout, f_total_vote_weight).
                       Blocks with no operations have op_type_id=NULL (LEFT JOIN).
        Returns (first_block, last_num, num_blocks).
        """
        if not combined_rows:
            return -1, 0, 0

        block_dates = {}
        block_vops = {}
        block_ops = {}

        for row in combined_rows:
            row_m = row._mapping
            block_num = row_m['block_num']
            block_dates[block_num] = row_m['date']

            op_type_id = row_m['op_type_id']
            if op_type_id is None:
                continue  # Block with no operations (LEFT JOIN null)

            if op_type_id == 0:  # VOTE - build dict from extracted columns
                body = {
                    'voter': row_m['f_voter'],
                    'author': row_m['f_author'],
                    'permlink': row_m['f_permlink'],
                    'weight': row_m['f_weight'],
                }
            elif op_type_id == 72:  # EFFECTIVE_COMMENT_VOTE
                body = {
                    'voter': row_m['f_voter'],
                    'author': row_m['f_author'],
                    'permlink': row_m['f_permlink'],
                    'weight': row_m['f_weight'],
                    'rshares': row_m['f_rshares'],
                    'pending_payout': row_m['f_pending_payout'],
                    'total_vote_weight': row_m['f_total_vote_weight'],
                }
            else:
                body = row_m['body']

            if op_type_id >= 50:
                if block_num not in block_vops:
                    block_vops[block_num] = []
                block_vops[block_num].append((op_type_id, body))
            else:
                if block_num not in block_ops:
                    block_ops[block_num] = []
                block_ops[block_num].append((op_type_id, body))

        sorted_blocks = sorted(block_dates.keys())
        first_block = sorted_blocks[0]
        last_num = first_block

        try:
            for block_num in sorted_blocks:
                date = block_dates[block_num]
                cls._current_block_date = date

                if cls._head_block_date is None:
                    cls._head_block_date = cls._current_block_date

                vops = block_vops.get(block_num)
                ops = block_ops.get(block_num)

                if vops or ops:
                    is_safe_cashout = block_num <= cls._last_safe_cashout_block
                    ineffective_deleted_ops = cls._process_vops_flat(
                        Posts.comment_payout_ops, vops or [], date, block_num, is_safe_cashout
                    )
                    if ops:
                        cls._process_ops_flat(ops, block_num, ineffective_deleted_ops)

                cls._head_block_date = cls._current_block_date
                last_num = block_num
        except Exception as e:
            log.error("exception encountered block %d", last_num + 1)
            raise e

        return first_block, last_num, len(block_dates)

    @classmethod
    def _process_vops_flat(
        cls, comment_payout_ops: dict, vops: list, date: str, block_num: int, is_safe_cashout: bool
    ) -> dict:
        """Process virtual operations from flat rows. Equivalent to prepare_vops()."""

        def get_empty_ops():
            return {
                VirtualOperationType.AUTHOR_REWARD: None,
                VirtualOperationType.COMMENT_REWARD: None,
                VirtualOperationType.EFFECTIVE_COMMENT_VOTE: None,
                VirtualOperationType.COMMENT_PAYOUT_UPDATE: None,
            }

        ineffective_deleted_ops = {}

        for op_type_id, op_value in vops:
            start = OPSM.start()

            op_value['block_num'] = block_num
            key = f"{op_value['author']}/{op_value['permlink']}"

            if op_type_id == 51:  # AUTHOR_REWARD
                if key not in comment_payout_ops:
                    comment_payout_ops[key] = get_empty_ops()
                comment_payout_ops[key][VirtualOperationType.AUTHOR_REWARD] = (op_value, date)

            elif op_type_id == 53:  # COMMENT_REWARD
                if key not in comment_payout_ops:
                    comment_payout_ops[key] = get_empty_ops()
                comment_payout_ops[key][VirtualOperationType.EFFECTIVE_COMMENT_VOTE] = None
                comment_payout_ops[key][VirtualOperationType.COMMENT_REWARD] = (op_value, date)

            elif op_type_id == 72:  # EFFECTIVE_COMMENT_VOTE
                if block_num < 905693:
                    op_value["rshares"] *= 1000000
                Votes.effective_comment_vote_op(op_value)

                if not is_safe_cashout:
                    if key not in comment_payout_ops:
                        comment_payout_ops[key] = get_empty_ops()
                    comment_payout_ops[key][VirtualOperationType.EFFECTIVE_COMMENT_VOTE] = (op_value, date)

            elif op_type_id == 61:  # COMMENT_PAYOUT_UPDATE
                if key not in comment_payout_ops:
                    comment_payout_ops[key] = get_empty_ops()
                comment_payout_ops[key][VirtualOperationType.COMMENT_PAYOUT_UPDATE] = (op_value, date)

            elif op_type_id == 73:  # INEFFECTIVE_DELETE_COMMENT
                ineffective_deleted_ops[key] = {}

            OPSM.op_stats(cls._OP_STAT_NAMES.get(op_type_id, str(op_type_id)), OPSM.stop(start))

        return ineffective_deleted_ops

    @classmethod
    def _process_ops_flat(cls, ops: list, block_num: int, ineffective_deleted_ops: dict) -> None:
        """Process regular operations from flat rows. Equivalent to the inner loop of _process()."""

        def try_register_account(account_name, op, op_details):
            if not Accounts.register(account_name, op_details, cls._head_block_date, block_num):
                log.error(f"Failed to register account {account_name} from operation: {op}")

        for op_type_id, op in ops:
            start = OPSM.start()

            op['block_num'] = block_num

            if op_type_id == 14:  # POW
                try_register_account(op['worker_account'], op, None)
            elif op_type_id == 30:  # POW_2
                try_register_account(op['work']['value']['input']['worker_account'], op, None)
            elif op_type_id == 9:  # ACCOUNT_CREATE
                try_register_account(op['new_account_name'], op, op)
            elif op_type_id == 41:  # ACCOUNT_CREATE_WITH_DELEGATION
                try_register_account(op['new_account_name'], op, op)
            elif op_type_id == 23:  # CREATE_CLAIMED_ACCOUNT
                try_register_account(op['new_account_name'], op, op)
            elif op_type_id == 10:  # ACCOUNT_UPDATE
                Accounts.update_op(op, False)
            elif op_type_id == 43:  # ACCOUNT_UPDATE_2
                Accounts.update_op(op, True)
            elif op_type_id == 1:  # COMMENT
                Posts.comment_op(op, cls._head_block_date)
            elif op_type_id == 17:  # DELETE_COMMENT
                key = f"{op['author']}/{op['permlink']}"
                if key not in ineffective_deleted_ops:
                    Posts.delete_op(op, cls._head_block_date)
            elif op_type_id == 19:  # COMMENT_OPTION
                # Flush pending comments first so they get stable post IDs
                if Posts._pending_comment_ops:
                    Posts.flush_pending_comment_ops()
                Posts.comment_options_op(op)
            elif op_type_id == 0:  # VOTE
                Votes.vote_op(op, cls._head_block_date)
            elif op_type_id == 18:  # CUSTOM_JSON
                op_id = op.get('id')
                if op_id == 'follow':
                    # Follow and reblog ops share custom_json id='follow'.
                    # SQL handles follows; reblogs still need Python processing.
                    json_str = op.get('json', '')
                    if isinstance(json_str, str) and json_str.lstrip().startswith('["reblog"'):
                        CustomOp.process_op(op, block_num, cls._head_block_date)
                    # else: follow op, handled by SQL procedure
                elif op_id == 'community':
                    # Community ops need the flush — they do immediate SQL lookups on posts
                    if Posts._pending_comment_ops:
                        Posts.flush_pending_comment_ops()
                    CustomOp.process_op(op, block_num, cls._head_block_date)
                else:
                    CustomOp.process_op(op, block_num, cls._head_block_date)

            OPSM.op_stats(cls._OP_STAT_NAMES.get(op_type_id, str(op_type_id)), OPSM.stop(start))

    @classmethod
    def process_multi(cls, blocks, is_massive_sync: bool) -> None:
        """Batch-process blocks; wrapped in a transaction."""
        time_start = OPSM.start()

        if is_massive_sync:
            DbAdapterHolder.common_block_processing_db().query_no_return("START TRANSACTION")

        first_block, last_num = cls.process_blocks(blocks)

        if is_massive_sync:
            # Batch-process accumulated comment operations in a single SQL call
            Posts.flush_pending_comment_ops()
            Notify.flush_lastread()
            DbAdapterHolder.common_block_processing_db().query_no_return("COMMIT")

        if not is_massive_sync:
            log.info("[PROCESS MULTI] Flushing data in 1 thread")
            cls.flush_data_in_1_thread()
            if first_block > -1:
                log.info("[PROCESS MULTI] Tables updating in live synchronization")
                cls.on_live_blocks_processed(first_block)
                cls._periodic_actions(blocks[0])

        if is_massive_sync:
            cls.flush_data_in_n_threads()

        log.info(f"[PROCESS MULTI] {len(blocks)} blocks in {OPSM.stop(time_start):.4f}s")

    @classmethod
    def process_multi_flat(cls, op_rows, block_dates: dict, num_blocks: int) -> None:
        """Batch-process flat operation rows for massive sync."""
        time_start = OPSM.start()

        db = DbAdapterHolder.common_block_processing_db()
        db.query_no_return("START TRANSACTION")

        first_block, last_num = cls.process_blocks_flat(op_rows, block_dates)

        Posts.flush_pending_comment_ops()

        # Process follow operations entirely in SQL (after accounts are created)
        if first_block > -1:
            cls._process_follows_in_sql(db, first_block, last_num)

        Notify.flush_lastread()
        db.query_no_return("COMMIT")

        cls.flush_data_in_n_threads()

        log.info(f"[PROCESS MULTI FLAT] {num_blocks} blocks in {OPSM.stop(time_start):.4f}s")

    @classmethod
    def process_multi_flat_extended(cls, op_rows, block_dates: dict, num_blocks: int) -> None:
        """Batch-process extended flat rows (with extracted vote fields) for massive sync."""
        time_start = OPSM.start()

        db = DbAdapterHolder.common_block_processing_db()
        db.query_no_return("START TRANSACTION")

        first_block, last_num = cls.process_blocks_flat_extended(op_rows, block_dates)

        Posts.flush_pending_comment_ops()

        # Process follow operations entirely in SQL (after accounts are created)
        if first_block > -1:
            cls._process_follows_in_sql(db, first_block, last_num)

        Notify.flush_lastread()
        db.query_no_return("COMMIT")

        cls.flush_data_in_n_threads()

        log.info(f"[PROCESS MULTI FLAT EXT] {num_blocks} blocks in {OPSM.stop(time_start):.4f}s")

    @classmethod
    def process_multi_combined_extended(cls, combined_rows, num_blocks: int) -> None:
        """Batch-process combined extended rows (ops + dates + vote fields) for massive sync."""
        time_start = OPSM.start()

        db = DbAdapterHolder.common_block_processing_db()
        db.query_no_return("START TRANSACTION")

        first_block, last_num, _actual_blocks = cls.process_blocks_combined_extended(combined_rows)

        Posts.flush_pending_comment_ops()

        # Process follow operations entirely in SQL (after accounts are created)
        if first_block > -1:
            cls._process_follows_in_sql(db, first_block, last_num)

        Notify.flush_lastread()
        db.query_no_return("COMMIT")

        cls.flush_data_in_n_threads()

        log.info(f"[PROCESS MULTI COMBINED EXT] {num_blocks} blocks in {OPSM.stop(time_start):.4f}s")

    @classmethod
    def _process_follows_in_sql(cls, db, first_block: int, last_block: int) -> None:
        """Process follow operations entirely in SQL, returning notification data."""
        start = OPSM.start()
        notification_rows = db.query_all(
            text("SELECT * FROM hivemind_app.process_follows_for_blocks(:first, :last)").bindparams(
                first=first_block, last=last_block
            ),
            is_prepared=True,
        )
        for row in notification_rows:
            m = row._mapping
            if not NotificationCache.should_skip_for_block(m['block_num']):
                NotificationCache.follow_notifications_to_flush.append(
                    (
                        escape_characters(m['follower_name']),
                        escape_characters(m['following_name']),
                        m['block_num'],
                        Follow._counter.increment(m['block_num']),
                    )
                )
        OPSM.op_stats('follow_sql', OPSM.stop(start))

    @classmethod
    def _periodic_actions(cls, block_raw) -> None:
        """Actions performed at a given time, calculated on the basis of the current block number"""
        block = BlockHiveDb(block_raw, MassiveBlocksDataProviderHiveDb._operation_id_to_enum)

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
            if not Accounts.register(account_name, op_details, cls._head_block_date, num):
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
                elif op_type == OperationType.CUSTOM_JSON:  # follow/reblog/community ops
                    if DbState.is_massive_sync() and Posts._pending_comment_ops:
                        Posts.flush_pending_comment_ops()
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
