"""Blocks processor."""

import logging
from concurrent.futures import ThreadPoolExecutor
from time import perf_counter

from hive.conf import ONE_WEEK_IN_BLOCKS, SCHEMA_NAME, Conf
from hive.db.adapter import Db
from hive.db.db_state import DbState
from hive.indexer.accounts import Accounts
from hive.indexer.community import Community
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.indexer.follow import Follow
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
    _notification_min_block = None  # cached 90-day notification threshold

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
    def process_multi_sql(cls, first_block: int, last_block: int) -> None:
        """Process a batch of blocks using pure SQL functions.

        Replaces the Python dispatch loop with SQL functions that read from
        a staging table. Only PostDataCache body merging remains in Python.

        Phases:
          1.    Load staging table (single scan of operations_view)
          2.    Account registration + community state changes (single transaction)
          3.    Post/comment processing (must commit before votes/reblogs)
          3a.   Community post-targeting ops + mute propagation (skipped before community start)
          3.5.  Votes (rshares deferred to finalization)
          4+3b. Parallel: SQL entity processing + Python body merging (overlapped)
          5.    PostDataCache flush
          6.    Parallel notification flush (skipped for blocks before 90-day window)
        """
        time_start = OPSM.start()
        phase_times = {}
        db = DbAdapterHolder.common_block_processing_db()

        # Phase 1: Load staging table (single scan of operations_view)
        t0 = perf_counter()
        db.query_no_return("START TRANSACTION")
        db.query_no_return(f"SELECT {SCHEMA_NAME}.load_ops_staging({first_block}, {last_block})")
        db.query_no_return("COMMIT")
        phase_times['load'] = perf_counter() - t0

        # Phase 2: Account registration + community state changes (single transaction)
        t0 = perf_counter()
        db.query_no_return("START TRANSACTION")
        db.query_no_return(f"SELECT {SCHEMA_NAME}.process_accounts_from_staging({Community.start_block})")
        db.query_no_return(f"SELECT {SCHEMA_NAME}.process_community_from_staging({Community.start_block}, 1)")
        db.query_no_return("COMMIT")
        phase_times['accounts_community'] = perf_counter() - t0

        # Phase 3: Post/comment processing (must commit before votes/reblogs)
        t0 = perf_counter()
        db.query_no_return("START TRANSACTION")
        post_results = db.query_all(f"SELECT * FROM {SCHEMA_NAME}.process_posts_from_staging({Community.start_block})")
        db.query_no_return("COMMIT")
        phase_times['posts'] = perf_counter() - t0

        # Phase 3a: Community post-targeting ops (mutePost, unmutePost, pinPost, etc.)
        # Skip entirely when batch is before community support start block — no community
        # ops or muted parents to propagate.
        t0 = perf_counter()
        if last_block >= Community.start_block:
            db.query_no_return("START TRANSACTION")
            db.query_no_return(f"SELECT {SCHEMA_NAME}.process_community_from_staging({Community.start_block}, 2)")
            db.query_no_return(f"SELECT {SCHEMA_NAME}.propagate_muted_parent_for_batch({first_block}, {last_block})")
            db.query_no_return("COMMIT")
        phase_times['community_post'] = perf_counter() - t0

        # Phase 3.5: Votes (rshares deferred to finalization; must run BEFORE payouts).
        t0 = perf_counter()
        Votes.db.query_no_return("START TRANSACTION")
        Votes.db.query_no_return(f"SELECT {SCHEMA_NAME}.process_votes_from_staging({cls._last_safe_cashout_block})")
        Votes.db.query_no_return("COMMIT")
        phase_times['votes'] = perf_counter() - t0

        # Phase 4+3b: Overlap Python body merging with parallel SQL entity processing.
        # PostDataCache._data is only accessed by the main thread; Phase 4 tasks use
        # separate DB connections and don't touch hive_post_data, so no conflict.
        #
        # IMPORTANT: process_follows_for_blocks, process_account_updates_from_staging,
        # and process_lastread_from_staging all UPDATE hive_accounts. Running them on
        # separate connections causes deadlocks when two transactions lock overlapping
        # account rows in different orders. We run account_updates and lastread on the
        # main thread (after parallel completes) to serialize hive_accounts access.
        # Both are trivially fast (<1ms).
        t0 = perf_counter()
        phase4_tasks = [
            (Reblog.db, f"SELECT {SCHEMA_NAME}.process_reblogs_from_staging()"),
            (Follow.db, f"SELECT * FROM {SCHEMA_NAME}.process_follows_for_blocks({first_block}, {last_block})"),
            (Posts.db, f"SELECT {SCHEMA_NAME}.process_payouts_from_staging({cls._last_safe_cashout_block})"),
        ]

        # Launch Phase 4 SQL tasks in background threads
        pool = ThreadPoolExecutor(max_workers=len(phase4_tasks))
        futures = []

        def run_one_task(db_conn, sql):
            db_conn.query_no_return("START TRANSACTION")
            try:
                db_conn.query_all_raw(sql)
                db_conn.query_no_return("COMMIT")
            except Exception:
                try:
                    db_conn.query_no_return("ROLLBACK")
                except Exception:
                    pass
                raise

        for db_conn, sql in phase4_tasks:
            futures.append(pool.submit(run_one_task, db_conn, sql))

        # Phase 3b: Process post results on main thread while Phase 4 runs in parallel
        t0_cache = perf_counter()
        cls._process_post_results_for_cache(post_results)
        phase_times['cache_merge'] = perf_counter() - t0_cache

        # Wait for all Phase 4 tasks to complete
        for f in futures:
            f.result()
        pool.shutdown(wait=False)

        # Phase 4b: Account metadata + lastread (must run AFTER follows to avoid
        # deadlocks on hive_accounts — all three UPDATE the same table).
        db.query_no_return("START TRANSACTION")
        db.query_no_return(f"SELECT {SCHEMA_NAME}.process_account_updates_from_staging()")
        db.query_no_return(f"SELECT {SCHEMA_NAME}.process_lastread_from_staging()")
        db.query_no_return("COMMIT")
        phase_times['parallel'] = perf_counter() - t0

        # Phase 5: PostDataCache flush (on its own connection; flush() manages its own tx)
        t0 = perf_counter()
        PostDataCache.flush()
        phase_times['flush'] = perf_counter() - t0

        # Phase 6: Parallel notification flush
        # Vote notifications are deferred to finalization (_finish_vote_notifications)
        # because scoring uses payout data that isn't available during massive sync.
        # Post/follow/reblog notifications are skipped for blocks older than the 90-day
        # notification window (they would never appear in user notification feeds).
        t0 = perf_counter()
        if cls._notification_min_block is None:
            cls._notification_min_block = db.query_one(f"SELECT {SCHEMA_NAME}.block_before_irreversible('90 days')")
        if last_block > cls._notification_min_block:
            phase6_tasks = [
                (
                    PostNotificationCache.db,
                    f"SELECT {SCHEMA_NAME}.flush_post_notifications_for_blocks({first_block}, {last_block})",
                ),
                (
                    FollowNotificationCache.db,
                    f"SELECT {SCHEMA_NAME}.flush_follow_notifications_for_blocks({first_block}, {last_block})",
                ),
                (
                    ReblogNotificationCache.db,
                    f"SELECT {SCHEMA_NAME}.flush_reblog_notifications_for_blocks({first_block}, {last_block})",
                ),
            ]
            cls._run_parallel_sql(phase6_tasks)
        phase_times['notify'] = perf_counter() - t0

        total = sum(phase_times.values())
        log.info(
            "[PHASE-SUMMARY] blocks=%d-%d total=%.3fs %s",
            first_block,
            last_block,
            total,
            ' '.join(f'{k}={v:.3f}' for k, v in phase_times.items()),
        )

        OPSM.stop(time_start)

    @classmethod
    def process_live_block_sql(cls, first_block: int, last_block: int) -> None:
        """Process blocks in live sync using SQL functions (sequential, shared connection).

        All phases run sequentially on the shared connection (no parallelism).
        After SQL processing, live-sync-specific post-processing is performed
        (children count, root_id, feed cache, periodic actions).
        """
        time_start = OPSM.start()
        db = DbAdapterHolder.common_block_processing_db()

        # Phase 1: Load staging table
        db.query_no_return(f"SELECT {SCHEMA_NAME}.load_ops_staging({first_block}, {last_block})")

        # Phase 2: Account registration
        db.query_no_return(f"SELECT {SCHEMA_NAME}.process_accounts_from_staging({Community.start_block})")

        # Phase 3: Post/comment processing
        post_results = db.query_all(f"SELECT * FROM {SCHEMA_NAME}.process_posts_from_staging({Community.start_block})")

        # Phase 3b: PostDataCache body merging (Python)
        cls._process_post_results_for_cache(post_results)

        # Phase 4: Entity processing (sequential on shared connection)
        db.query_no_return(f"SELECT {SCHEMA_NAME}.process_votes_from_staging({cls._last_safe_cashout_block})")

        # Live sync: update post rshares immediately (API needs current values)
        affected_posts = db.query_col(
            f"SELECT DISTINCT post_id FROM {SCHEMA_NAME}.hive_votes "
            f"WHERE block_num BETWEEN {first_block} AND {last_block}"
        )
        if affected_posts:
            db.query_no_return(
                f"SELECT * FROM {SCHEMA_NAME}.update_posts_rshares(:post_ids)",
                post_ids=affected_posts,
            )

        db.query_no_return(f"SELECT {SCHEMA_NAME}.process_reblogs_from_staging()")
        db.query_no_return(f"SELECT * FROM {SCHEMA_NAME}.process_follows_for_blocks({first_block}, {last_block})")
        db.query_no_return(f"SELECT {SCHEMA_NAME}.process_account_updates_from_staging()")
        db.query_no_return(f"SELECT {SCHEMA_NAME}.process_lastread_from_staging()")
        db.query_no_return(f"SELECT {SCHEMA_NAME}.process_payouts_from_staging({cls._last_safe_cashout_block})")
        db.query_no_return(f"SELECT {SCHEMA_NAME}.process_community_from_staging({Community.start_block})")

        # Phase 5: PostDataCache flush
        PostDataCache.flush()

        # Phase 6: Notifications (sequential)
        db.query_no_return(f"SELECT {SCHEMA_NAME}.flush_vote_notifications_for_blocks({first_block}, {last_block})")
        db.query_no_return(f"SELECT {SCHEMA_NAME}.flush_post_notifications_for_blocks({first_block}, {last_block})")
        db.query_no_return(f"SELECT {SCHEMA_NAME}.flush_follow_notifications_for_blocks({first_block}, {last_block})")
        db.query_no_return(f"SELECT {SCHEMA_NAME}.flush_reblog_notifications_for_blocks({first_block}, {last_block})")

        # Live sync post-processing
        log.info("[PROCESS LIVE SQL] Tables updating in live synchronization")
        cls.on_live_blocks_processed(first_block, last_block)
        cls._periodic_actions_by_num(last_block)

        log.info(
            "[PROCESS LIVE SQL] blocks %d-%d in %.4fs",
            first_block,
            last_block,
            OPSM.stop(time_start),
        )

    @classmethod
    def _process_post_results_for_cache(cls, post_results):
        """Process SQL post results for PostDataCache body merging.

        Each result row from process_posts_from_staging() contains the post_id,
        is_new_post flag, and the original op body (JSONB). For new posts, the
        full title/body/json is stored. For edits, diff patches are applied to
        the existing body.
        """
        for row in post_results:
            r = row._mapping
            post_id = r['post_id']
            is_new = r['is_new_post']
            op_body = r['op_body']

            if op_body is None:
                continue

            parent_author = op_body.get('parent_author', '')

            if is_new:
                post_data = dict(
                    title=op_body.get('title', '') or '',
                    body=op_body.get('body', '') or '',
                    json=op_body.get('json_metadata', '') or '',
                    is_root='true' if not parent_author else 'false',
                )
            else:
                body = op_body.get('body')
                new_body = Posts._merge_post_body(id=post_id, new_body_def=body) if body else None
                new_title = op_body.get('title') if op_body.get('title') else None
                new_json = op_body.get('json_metadata') if op_body.get('json_metadata') else None
                post_data = dict(title=new_title, body=new_body, json=new_json, is_root='false')

            PostDataCache.add_data(post_id, post_data, is_new)

    @staticmethod
    def _run_parallel_sql(tasks):
        """Run multiple SQL functions in parallel on separate DB connections.

        Each task is a (db_connection, sql_string) tuple. Each function runs
        in its own transaction on its own connection.
        """

        def run_one(db_conn, sql):
            db_conn.query_no_return("START TRANSACTION")
            try:
                db_conn.query_all_raw(sql)  # Consume any results
                db_conn.query_no_return("COMMIT")
            except Exception:
                try:
                    db_conn.query_no_return("ROLLBACK")
                except Exception:
                    pass
                raise

        if len(tasks) <= 1:
            for db_conn, sql in tasks:
                run_one(db_conn, sql)
            return

        with ThreadPoolExecutor(max_workers=len(tasks)) as pool:
            futures = [pool.submit(run_one, db_conn, sql) for db_conn, sql in tasks]
            for f in futures:
                f.result()  # Raises any exceptions from threads

    @classmethod
    def _periodic_actions_by_num(cls, block_num: int) -> None:
        """Periodic actions for live sync (hourly stats, community rank updates)."""
        if block_num % 1200 == 0:  # 1hour
            log.info(f"head block {block_num}")
            log.info("[SINGLE] hourly stats")
            log.info("[SINGLE] filling payout_stats_view executed")
            PayoutStats.generate(db=DbAdapterHolder.common_block_processing_db())
            Mentions.refresh()
        elif block_num % 200 == 0:  # 10min
            log.info("[SINGLE] 10min")
            log.info("[SINGLE] updating communities posts and rank")
            update_communities_posts_and_rank(db=DbAdapterHolder.common_block_processing_db())

    @staticmethod
    @time_it
    def on_live_blocks_processed(first_block: int, last_block: int = None) -> None:
        """Is invoked when processing of block range is done and received
        informations from hived are already stored in db
        """
        if last_block is None:
            last_block = first_block
        queries = [
            f"SELECT {SCHEMA_NAME}.update_hive_posts_children_count({first_block}, {last_block})",
            f"SELECT {SCHEMA_NAME}.update_hive_posts_root_id({first_block},{last_block})",
            f"SELECT {SCHEMA_NAME}.update_feed_cache({first_block}, {last_block})",
            f"SELECT {SCHEMA_NAME}.update_last_completed_block({last_block})",
            f"SELECT {SCHEMA_NAME}.prune_notification_cache({last_block})",
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
