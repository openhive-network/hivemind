"""Blocks processor."""

import contextlib
import logging
import os
import threading
from collections.abc import Callable
from concurrent.futures import Future, ThreadPoolExecutor
from time import perf_counter, sleep, time
from typing import Any, TypeVar

import psycopg2.extensions

from hive.conf import SCHEMA_NAME, Conf
from hive.db.adapter import Db, Row
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
from hive.indexer.ops_prefetch import OpsPrefetch
from hive.indexer.payouts import Payouts
from hive.indexer.post_data_cache import PostDataCache
from hive.indexer.posts import Posts
from hive.indexer.reblog import Reblog
from hive.indexer.votes import Votes
from hive.signals import set_exception_thrown
from hive.utils.communities_rank import update_communities_posts_and_rank
from hive.utils.payout_stats import PayoutStats
from hive.utils.stats import OPStatusManager as OPSM
from hive.utils.timer import time_it

log = logging.getLogger(__name__)

_T = TypeVar('_T')


def _timed[T](times: dict[str, float], name: str, run: Callable[[], T]) -> T:
    """Return run(), its time put into times[name], whether it returned or raised."""
    t0 = perf_counter()
    try:
        return run()
    finally:
        times[name] = perf_counter() - t0


def _format_times(times: dict[str, float]) -> str:
    return ' '.join(f'{k}={v:.3f}' for k, v in times.items())


_KILL_POINTS = ('stage_a_committed', 'payouts_committed', 'flush_committed')


def _parse_kill_point(value: str | None) -> tuple[str, int] | None:
    """--test-pipeline-kill's POINT:BLOCK as (POINT, BLOCK); raises ValueError for any other value."""
    if not value:
        return None
    point, sep, block = value.partition(':')
    if not sep or point not in _KILL_POINTS or not block.isdigit():
        raise ValueError(f"--test-pipeline-kill takes POINT:BLOCK, POINT one of {', '.join(_KILL_POINTS)}: {value!r}")
    return point, int(block)


class Blocks:
    """Processes blocks, dispatches work, manages the state of the database (blocks consistency, and numbers)."""

    _conf = None
    _head_block_date = None
    _current_block_date = None
    _last_safe_cashout_block = 0
    _vote_workers = 1
    _payout_workers = 1
    # The staging functions clear their tables with DELETE; every this many calls the
    # dead rows are dropped by one TRUNCATE of all of them (see reset_staging_tables).
    # Measured flat between 5 and 20 batches of 1000 blocks. The block bound keeps
    # larger massive batches from piling up more dead rows than ten of those.
    _STAGING_RESET_INTERVAL = 10
    _STAGING_RESET_BLOCKS = 10_000
    _calls_since_staging_reset = 0
    _blocks_since_staging_reset = 0
    # The same per stage, for pipelined massive sync's per-stage resets: [calls, blocks].
    _since_stage_reset = {'A': [0, 0], 'B': [0, 0]}

    # Pipelined massive sync: Stage A of a batch (load, accounts and communities, posts,
    # community post ops) runs while Stage B of the previous one (votes, payouts, reblogs,
    # follows, account updates, post data flush, notifications, vacuum) runs on its own thread
    # and connections. Each stage stays serial.
    _pipelined = False
    # Whether Stage B reads tables of its own, filled by each batch's handoff
    # (set_stage_b_handoff); None until set.
    _handoff_tables: bool | None = None
    _stage_b_pool: ThreadPoolExecutor | None = None
    _stage_b_future: Future[None] | None = None
    _stage_b_first_block: int | None = None
    _kill_point: tuple[str, int] | None = None
    # What Stage B waits on at the stage_a_committed kill point: never set, the process exits.
    _kill_hold = threading.Event()
    # Deadlocks (40P01) retried, per stage: running the stages side by side adds the
    # posts phase against the payouts' hive_posts updates.
    _deadlocks = {'A': 0, 'B': 0}
    # Stage B's Phase 4 lanes count theirs from threads of their own.
    _deadlocks_lock = threading.Lock()
    _MAX_DEADLOCK_RETRIES = 3

    @classmethod
    def setup(cls, conf: Conf):
        cls._conf = conf
        cls._vote_workers = conf.get('massive_vote_workers')
        cls._payout_workers = conf.get('massive_payout_workers')
        cls._pipelined = bool(conf.get('massive_sync_pipelined'))
        cls._kill_point = _parse_kill_point(conf.get('test_pipeline_kill'))
        if cls._kill_point is not None and cls._kill_point[0] == 'stage_a_committed' and not cls._pipelined:
            raise ValueError(
                '--test-pipeline-kill=stage_a_committed:BLOCK needs pipelined massive sync, '
                'which --massive-sync-pipelined=false turns off'
            )

    @classmethod
    def is_pipelined(cls) -> bool:
        return cls._pipelined

    @classmethod
    def set_head_date(cls):
        head_date = cls.head_date()
        if head_date == '':
            cls._head_block_date = None
            cls._current_block_date = None
        else:
            cls._head_block_date = head_date
            cls._current_block_date = head_date

    @classmethod
    def setup_own_db_access(cls, shared_db_adapter: Db) -> None:
        if DbState.is_massive_sync():
            DbAdapterHolder.open_common_blocks_in_background_processing_db()
            if cls._pipelined:
                DbAdapterHolder.open_stage_b_processing_db()

        PostDataCache.setup_own_db_access(shared_db_adapter, "PostDataCache")
        Votes.setup_own_db_access(shared_db_adapter, "Votes")
        Votes.setup_worker_db_access(shared_db_adapter, cls._vote_workers)
        Follow.setup_own_db_access(shared_db_adapter, "Follow")
        Payouts.setup_own_db_access(shared_db_adapter, "Payouts")
        Payouts.setup_worker_db_access(shared_db_adapter, cls._payout_workers)
        Reblog.setup_own_db_access(shared_db_adapter, "Reblog")
        Notify.setup_own_db_access(shared_db_adapter, "Notify")
        Accounts.setup_own_db_access(shared_db_adapter, "Accounts")
        Mentions.setup_own_db_access(shared_db_adapter, "Mentions")
        NotificationCache.setup_own_db_access(shared_db_adapter, "NotificationCache")
        VoteNotificationCache.setup_own_db_access(shared_db_adapter, "VoteNotificationCache")
        PostNotificationCache.setup_own_db_access(shared_db_adapter, "PostNotificationCache")
        FollowNotificationCache.setup_own_db_access(shared_db_adapter, "FollowNotificationCache")
        ReblogNotificationCache.setup_own_db_access(shared_db_adapter, "ReblogNotificationCache")

    @classmethod
    def close_own_db_access(cls) -> None:
        cls._shut_down_stage_b()
        DbAdapterHolder.close_common_blocks_in_background_processing_db()
        DbAdapterHolder.close_stage_b_processing_db()

        PostDataCache.close_own_db_access()
        Votes.close_own_db_access()
        Follow.close_own_db_access()
        Payouts.close_own_db_access()
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
        # Check current block first to avoid expensive query when at block 0
        # (hafd.blocks has no usable index during REINDEX, causing full table scan)
        current = Db.instance().query_one(f"SELECT hive.app_get_current_block_num('{SCHEMA_NAME}')")
        if not current:
            return ''
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
            # (while hived replays, every block up to LIB once LIB is 7 days old)
            cls._last_safe_cashout_block = Db.instance().query_one(
                f"SELECT {SCHEMA_NAME}.block_before_irreversible('7 days')"
            )

    @classmethod
    def process_multi_sql(
        cls,
        first_block: int,
        last_block: int,
        ops_prefetch: OpsPrefetch | None = None,
        next_range: tuple[int, int] | None = None,
    ) -> None:
        """Process a batch of blocks using pure SQL functions, its Stage B after its Stage A.

        Replaces the Python dispatch loop with SQL functions that read from
        a staging table. Only PostDataCache body merging remains in Python.

        With `ops_prefetch`, the staging table is filled from what it loaded for
        this batch when that covers it, and once it is filled `ops_prefetch`
        starts loading `next_range` (when given) while the other phases run.

        Phases (Stage A: 1-3a, _run_stage_a; Stage B: 4-7, _run_stage_b):
          1.    Load staging table (single scan of operations_view, or the prefetched rows)
          2.    Account registration + community state changes (single transaction)
          3.    Post/comment processing (must commit before votes/reblogs)
          3a.   Community post-targeting ops + mute propagation (skipped before community start)
          4+3b. Parallel lanes: votes then payouts, reblogs, follows; Python body merging beside them
          4b.   Account metadata, lastread and post counts
          5.    PostDataCache flush
          6.    Parallel notification flush (skipped for blocks before 90-day window)
          7.    Boundary vacuum
        """
        time_start = OPSM.start()
        phase_times: dict[str, float] = {}
        db = DbAdapterHolder.common_block_processing_db()

        post_results, post_data_applied, prefetched = cls._run_stage_a(
            db, first_block, last_block, ops_prefetch, next_range, phase_times
        )
        if cls._handoff_tables:
            t0 = perf_counter()
            cls._hand_off_to_stage_b(db)
            phase_times['handoff'] = perf_counter() - t0
        cls._run_stage_b(
            db, first_block, last_block, post_results, post_data_applied, phase_times, cls._last_safe_cashout_block
        )
        cls._log_phase_summary(first_block, last_block, phase_times, prefetched)

        OPSM.stop(time_start)

    @classmethod
    def process_multi_sql_pipelined(
        cls,
        first_block: int,
        last_block: int,
        ops_prefetch: OpsPrefetch | None = None,
        next_range: tuple[int, int] | None = None,
    ) -> None:
        """Process a batch's Stage A, then hand the batch to Stage B, which runs it on its own thread.

        Returns once Stage B of the previous batch has ended (raising its exception when it
        failed) and this batch's has started: the caller may then start the next batch's
        Stage A, which runs beside it. Stage B deletes the batch's _batch_queue row once it
        has committed everything. Needs the handoff tables (set_stage_b_handoff(db, True)).
        """
        time_start = OPSM.start()
        phase_times: dict[str, float] = {}
        db = DbAdapterHolder.common_block_processing_db()
        if DbAdapterHolder._stage_b_processing_db is None:
            DbAdapterHolder.open_stage_b_processing_db()
        # set for this batch (set_end_of_sync_lib); the next batch's start sets it again while this Stage B runs
        last_safe_cashout_block = cls._last_safe_cashout_block

        started = time()
        deadlocks = cls._deadlocks['A']
        post_results, post_data_applied, prefetched = cls._run_stage_a(
            db, first_block, last_block, ops_prefetch, next_range, phase_times
        )
        ended = time()
        cls._kill_if_at('stage_a_committed', cls._stage_b_first_block)

        cls.wait_for_stage_b()
        waited = time() - ended
        t0 = perf_counter()
        cls._hand_off_to_stage_b(db)
        phase_times['handoff'] = perf_counter() - t0
        log.info(
            "[STAGE-TIMING] blocks=%d-%d stage=A start=%.3f end=%.3f elapsed=%.3f deadlocks=%d "
            "wait_for_b=%.3f handoff=%.3f %s",
            first_block,
            last_block,
            started,
            ended,
            ended - started,
            cls._deadlocks['A'] - deadlocks,
            waited,
            phase_times['handoff'],
            _format_times({k: v for k, v in phase_times.items() if k != 'handoff'}),
        )

        if cls._stage_b_pool is None:
            cls._stage_b_pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix='stage_b')
        cls._stage_b_first_block = first_block
        cls._stage_b_future = cls._stage_b_pool.submit(
            cls._stage_b_task,
            first_block,
            last_block,
            post_results,
            post_data_applied,
            phase_times,
            prefetched,
            last_safe_cashout_block,
        )
        OPSM.stop(time_start)

    @classmethod
    def _stage_b_task(
        cls,
        first_block: int,
        last_block: int,
        post_results: list[Row],
        post_data_applied: bool,
        phase_times: dict[str, float],
        prefetched: float | None,
        last_safe_cashout_block: int,
    ) -> None:
        """Stage B of a pipelined batch, on the Stage B thread and connection; deletes the batch's _batch_queue row."""
        try:
            if cls._kill_point == ('stage_a_committed', first_block):
                log.warning(
                    "[PIPELINE-KILL] holding Stage B of blocks %d-%d until the next batch's Stage A commits",
                    first_block,
                    last_block,
                )
                cls._kill_hold.wait()

            started = time()
            deadlocks = cls._deadlocks['B']
            db = DbAdapterHolder.stage_b_processing_db()
            a_phases = set(phase_times)
            lane_times = cls._run_stage_b(
                db, first_block, last_block, post_results, post_data_applied, phase_times, last_safe_cashout_block
            )
            cls._in_transaction(db, f"DELETE FROM {SCHEMA_NAME}._batch_queue WHERE first_block = {first_block:d}")
            ended = time()
            log.info(
                "[STAGE-TIMING] blocks=%d-%d stage=B start=%.3f end=%.3f elapsed=%.3f deadlocks=%d %s %s",
                first_block,
                last_block,
                started,
                ended,
                ended - started,
                cls._deadlocks['B'] - deadlocks,
                _format_times({k: v for k, v in phase_times.items() if k not in a_phases}),
                _format_times(lane_times),
            )
            cls._log_phase_summary(first_block, last_block, phase_times, prefetched)
        except Exception:
            log.exception("Exception caught in Stage B of blocks %d-%d", first_block, last_block)
            set_exception_thrown()
            raise

    @classmethod
    def wait_for_stage_b(cls) -> None:
        """Wait for the running Stage B, if any, to end; raises its exception (once) when it failed."""
        future, cls._stage_b_future = cls._stage_b_future, None
        if future is not None:
            future.result()

    @classmethod
    def raise_stage_b_error(cls) -> None:
        """Raise the exception of a Stage B that has ended with one, without waiting for a running one."""
        if cls._stage_b_future is not None and cls._stage_b_future.done():
            cls.wait_for_stage_b()

    @classmethod
    def _shut_down_stage_b(cls) -> None:
        try:
            cls.wait_for_stage_b()
        except Exception:
            log.warning("Stage B failed before shutdown; its batch stays in _batch_queue for the replay", exc_info=True)
        if cls._stage_b_pool is not None:
            cls._stage_b_pool.shutdown(wait=True)
            cls._stage_b_pool = None

    @classmethod
    def set_stage_b_handoff(cls, db: Db, tables: bool) -> None:
        """Make Stage B read tables of its own, filled by each batch's handoff (pipelined massive sync), or views of
        Stage A's tables (set_stage_b_handoff in massive_sync.sql)."""
        if cls._handoff_tables is tables:
            return
        cls._in_transaction(db, f"SELECT {SCHEMA_NAME}.set_stage_b_handoff({'TRUE' if tables else 'FALSE'})")
        cls._handoff_tables = tables

    @classmethod
    def _hand_off_to_stage_b(cls, db: Db) -> None:
        cls._in_transaction(db, f"SELECT {SCHEMA_NAME}.hand_off_to_stage_b()")

    @classmethod
    def process_stage_b_of_batch(cls, first_block: int, last_block: int) -> None:
        """Replay Stage B of a batch whose Stage A committed, from its operations and posts phase results, reloaded.

        The operations are read from HAF's tables (prefetch_ops_staging), as the context's
        views may already show the next batch's range. Its Stage A, which the next batch's
        may have run on top of, is not run again.
        """
        time_start = OPSM.start()
        phase_times: dict[str, float] = {}
        db = DbAdapterHolder.common_block_processing_db()

        t0 = perf_counter()
        db.query_no_return("START TRANSACTION")
        try:
            loaded = db.query_one(f"SELECT {SCHEMA_NAME}.prefetch_ops_staging({first_block:d}, {last_block:d})")
            if loaded != last_block:
                raise RuntimeError(
                    f"Cannot replay Stage B of blocks {first_block}-{last_block}: "
                    f"HAF's tables hold them up to block {loaded} only"
                )
            db.query_no_return(f"SELECT {SCHEMA_NAME}.load_ops_staging_from_prefetch({first_block:d}, {last_block:d})")
            post_data_applied = bool(
                db.query_one(
                    f"SELECT post_data_applied FROM {SCHEMA_NAME}._batch_queue WHERE first_block = {first_block:d}"
                )
            )
            post_results = db.query_all(f"SELECT * FROM {SCHEMA_NAME}.restore_batch_post_results({first_block:d})")
            db.query_no_return("COMMIT")
        except Exception:
            with contextlib.suppress(Exception):
                db.query_no_return("ROLLBACK")
            raise
        phase_times['load'] = perf_counter() - t0

        if cls._handoff_tables:
            t0 = perf_counter()
            cls._hand_off_to_stage_b(db)
            phase_times['handoff'] = perf_counter() - t0
        cls._run_stage_b(
            db, first_block, last_block, post_results, post_data_applied, phase_times, cls._last_safe_cashout_block
        )
        cls._log_phase_summary(first_block, last_block, phase_times, None)

        OPSM.stop(time_start)

    @classmethod
    def _run_stage_a(
        cls,
        db: Db,
        first_block: int,
        last_block: int,
        ops_prefetch: OpsPrefetch | None,
        next_range: tuple[int, int] | None,
        phase_times: dict[str, float],
    ) -> tuple[list[Row], bool, float | None]:
        """Run a batch's Stage A (phases 1-3a) on `db`.

        Returns the posts phase's rows, whether the batch's post data flush has committed,
        and how long the prefetch of the batch's operations ran (None when they were loaded
        here). Its last transaction marks the batch's Stage A applied (_batch_queue.stage_a_applied).
        """
        if cls._handoff_tables:
            # Before the load: what Stage A staged last is in Stage B's tables by now, and
            # this batch's rows must stay until its own handoff.
            t0 = perf_counter()
            cls._reset_stage_staging_tables_if_due(db, 'A', last_block - first_block + 1)
            phase_times['staging_reset_a'] = perf_counter() - t0

        # Phase 1: Load staging table (single scan of operations_view, or the
        # prefetched rows). The prefetch of the next range starts only after this
        # commit, as it overwrites the rows this load reads.
        # With the handoff tables, the prefetched rows are taken by a rename, not copied.
        t0 = perf_counter()
        prefetched = ops_prefetch.take(first_block, last_block) if ops_prefetch is not None else None
        db.query_no_return("START TRANSACTION")
        if prefetched is None:
            db.query_no_return(f"SELECT {SCHEMA_NAME}.load_ops_staging({first_block}, {last_block})")
        elif cls._handoff_tables:
            db.query_no_return(f"SELECT {SCHEMA_NAME}.take_prefetched_ops_staging({first_block}, {last_block})")
        else:
            db.query_no_return(f"SELECT {SCHEMA_NAME}.load_ops_staging_from_prefetch({first_block}, {last_block})")
        db.query_no_return("COMMIT")
        phase_times['load'] = perf_counter() - t0
        if ops_prefetch is not None and next_range is not None:
            ops_prefetch.start(*next_range)

        # Phase 2: Account registration + community state changes (single transaction)
        t0 = perf_counter()
        cls._retry_deadlocks(
            'A',
            "Accounts and communities",
            lambda: cls._in_transaction(
                db,
                f"SELECT {SCHEMA_NAME}.process_accounts_from_staging({Community.start_block})",
                f"SELECT {SCHEMA_NAME}.process_community_from_staging({Community.start_block}, 1)",
            ),
        )
        phase_times['accounts_community'] = perf_counter() - t0

        # Phase 3: Post/comment processing (must commit before votes/reblogs). The phase is
        # one transaction, its post id reservation included, so a deadlock retry is safe.
        t0 = perf_counter()
        post_results, post_data_applied = cls._retry_deadlocks(
            'A', "Posts phase", lambda: cls._process_batch_posts(db, first_block)
        )
        phase_times['posts'] = perf_counter() - t0

        # Phase 3a: Community post-targeting ops (mutePost, unmutePost, pinPost, etc.)
        # Skip entirely when batch is before community support start block — no community
        # ops or muted parents to propagate.
        # NOTE: propagate_muted_parent_for_batch is DEFERRED to finalization. During
        # MASSIVE_WITHOUT_INDEXES the parent_id index is dropped, making the recursive
        # CTE do a full sequential scan (~15s per call at 40M+ rows). A single pass at
        # finalization (with indexes) handles all accumulated mutes instantly.
        t0 = perf_counter()
        community_post = (
            [f"SELECT {SCHEMA_NAME}.process_community_from_staging({Community.start_block}, 2)"]
            if last_block >= Community.start_block
            else []
        )
        cls._retry_deadlocks(
            'A',
            "Community post ops",
            lambda: cls._in_transaction(
                db,
                *community_post,
                f"UPDATE {SCHEMA_NAME}._batch_queue SET stage_a_applied = TRUE WHERE first_block = {first_block:d}",
            ),
        )
        phase_times['community_post'] = perf_counter() - t0

        return post_results, post_data_applied, prefetched

    @classmethod
    def _run_stage_b(
        cls,
        db: Db,
        first_block: int,
        last_block: int,
        post_results: list[Row],
        post_data_applied: bool,
        phase_times: dict[str, float],
        last_safe_cashout_block: int,
    ) -> dict[str, float]:
        """Run a batch's Stage B (phases 4-7) on `db` and its phases' own connections, from what Stage A handed off.

        Payouts take `last_safe_cashout_block` as set_end_of_sync_lib set it for the batch.
        Returns the times of Phase 4's lanes and sub-phases, which overlap one another and
        are all within phase_times['parallel'].
        """
        # Phase 4+3b: three lanes, each on connections of its own, beside Python's body merge
        # (Phase 3b) on this thread:
        #   - votes, then (MASSIVE_WITH_INDEXES) the rshares update of the voted posts, then
        #     payouts (_run_votes_and_payouts);
        #   - reblogs;
        #   - follows.
        # Foreign keys are dropped through massive sync, so the votes lane takes no lock on
        # the hive_accounts rows the follows lock; it writes hive_votes and hive_posts, which
        # neither other lane writes. PostDataCache._data is only accessed by this thread, and
        # no lane touches hive_post_data. Each task runs in transactions of its own and only
        # a task rolled back as a deadlock (40P01) runs again: a reblogs task that committed
        # must not (its reblog inserts would draw hive_reblogs ids again).
        #
        # IMPORTANT: process_follows_for_blocks, process_account_updates_from_staging,
        # and process_lastread_from_staging all UPDATE hive_accounts. Running them on
        # separate connections causes deadlocks when two transactions lock overlapping
        # account rows in different orders. We run account_updates and lastread on the
        # main thread (after the lanes complete) to serialize hive_accounts access.
        # Both are trivially fast (<1ms).
        lane_times: dict[str, float] = {}
        t0 = perf_counter()
        lanes: dict[str, Callable[[], object]] = {
            'votes_payouts': lambda: cls._run_votes_and_payouts(
                db, first_block, last_block, last_safe_cashout_block, lane_times
            ),
            'reblogs': lambda: cls._run_task(
                Reblog.db, "Reblogs", f"SELECT {SCHEMA_NAME}.process_reblogs_from_staging({last_block:d})"
            ),
            'follows': lambda: cls._run_task(
                Follow.db,
                "Follows",
                f"SELECT * FROM {SCHEMA_NAME}.process_follows_for_blocks({first_block}, {last_block})",
            ),
        }
        with ThreadPoolExecutor(max_workers=len(lanes), thread_name_prefix='stage_b_lane') as pool:
            futures = [pool.submit(_timed, lane_times, name, run) for name, run in lanes.items()]
            if not post_data_applied:
                _timed(lane_times, 'cache_merge', lambda: cls._process_post_results_for_cache(post_results))
            errors = [f.exception() for f in futures]
        error = next((e for e in errors if e is not None), None)
        if error is not None:
            raise error

        # Phase 4b: Account metadata, lastread and post counts (must run AFTER follows to
        # avoid deadlocks on hive_accounts — all of them UPDATE the same table). The post
        # counts are the posts phase's Step 7g, run here so that Stage A writes no existing
        # hive_accounts row.
        _timed(
            lane_times,
            'account_updates',
            lambda: cls._retry_deadlocks(
                'B',
                "Account updates",
                lambda: cls._in_transaction(
                    db,
                    f"SELECT {SCHEMA_NAME}.process_account_updates_from_staging()",
                    f"SELECT {SCHEMA_NAME}.process_lastread_from_staging()",
                    f"SELECT {SCHEMA_NAME}.process_post_counts_from_staging({first_block:d})",
                ),
            ),
        )
        phase_times['parallel'] = perf_counter() - t0

        # Phase 5: PostDataCache flush (on its own connection; flush() manages its own tx)
        # Mentions parsing is skipped for blocks older than the 90-day notification
        # window, like the phase-6 flushes below: hive_mentions is pruned to that
        # window (live sync only) and its sole consumer is notification rendering,
        # so massive-era mentions would be built only to be bulk-deleted — and the
        # body re-reads they force are the flush statement's main detoast traffic.
        # Taken per batch: while hived replays, the window moves with HAF's irreversible block.
        t0 = perf_counter()
        notification_min_block = db.query_one(f"SELECT {SCHEMA_NAME}.block_before_irreversible('90 days')")
        PostDataCache.flush(mentions_after_block=notification_min_block, batch_first_block=first_block)
        phase_times['flush'] = perf_counter() - t0
        cls._kill_if_at('flush_committed', first_block)

        # Phase 6: Parallel notification flush
        # Vote notifications are deferred to finalization (_finish_vote_notifications)
        # because scoring uses payout data that isn't available during massive sync.
        # Post/follow/reblog notifications are skipped for blocks older than the 90-day
        # notification window (they would never appear in user notification feeds).
        t0 = perf_counter()
        if last_block > notification_min_block:
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

        # Phase 7: Boundary vacuum. Autovacuum is disabled on hive_post_data for
        # the duration of massive sync (its toast vacuums race the flush
        # statement's body reads); vacuums run here instead, between two of
        # Stage B's flushes (Stage A does not read hive_post_data), triggered by a
        # dead-tuple threshold. Rarely fires -- the table accrues dead toast
        # slowly -- so the phase is ~free. Pipelined, the shared connection is the
        # main loop's, busy with the next batch's iteration.
        t0 = perf_counter()
        if cls._pipelined:
            DbState.run_boundary_vacuums(db)
        else:
            DbState.run_boundary_vacuums()
        phase_times['vacuum'] = perf_counter() - t0

        t0 = perf_counter()
        if cls._handoff_tables:
            cls._reset_stage_staging_tables_if_due(db, 'B', last_block - first_block + 1)
        else:
            cls._reset_staging_tables_if_due(db, last_block - first_block + 1)
        phase_times['staging_reset'] = perf_counter() - t0
        return lane_times

    @classmethod
    def _run_votes_and_payouts(
        cls, db: Db, first_block: int, last_block: int, last_safe_cashout_block: int, times: dict[str, float]
    ) -> None:
        """Stage B's votes lane: votes, the rshares update of the voted posts (MASSIVE_WITH_INDEXES), payouts.

        Votes run before the rshares update, which reads them, and the rshares update before
        the payouts, as both update the voted posts' hive_posts rows. Each sub-phase's time
        goes into `times`.
        """
        cls._process_votes_massive(times)

        # Incremental rshares update for MASSIVE_WITH_INDEXES mode. When indexes are
        # enabled, we must update rshares incrementally for votes processed in this batch.
        # During MASSIVE_WITHOUT_INDEXES (initial sync), indexes don't exist so this is
        # skipped — the full recalculate_all_posts_votes_and_children runs at finalization.
        # During MASSIVE_WITH_INDEXES (catch-up after restart or post-finalization gap),
        # indexes exist and the full recalculation won't re-run, so incremental updates are
        # essential. On `db`: this thread is the only one using it while the lanes run.
        if DbState.are_indexes_enabled():
            t0 = perf_counter()
            affected_posts = db.query_col(
                f"SELECT DISTINCT post_id FROM {SCHEMA_NAME}.hive_votes "
                f"WHERE block_num BETWEEN {first_block} AND {last_block}"
            )
            if affected_posts:
                # Its hive_posts rows are shared with the next batch's posts phase; both lock
                # them in id order, so the retry is only a safety net.
                cls._retry_deadlocks(
                    'B',
                    "Rshares update",
                    lambda: cls._in_transaction(
                        db, (f"SELECT * FROM {SCHEMA_NAME}.update_posts_rshares(:post_ids)", affected_posts)
                    ),
                )
            times['rshares_incr'] = perf_counter() - t0

        _timed(times, 'payouts', lambda: cls._process_payouts_massive(last_safe_cashout_block))
        cls._kill_if_at('payouts_committed', first_block)

    @classmethod
    def _run_task(cls, db_conn: Db | None, what: str, sql: str) -> None:
        """Run `sql` in a transaction of its own on `db_conn`, again when it is rolled back as a deadlock."""
        if db_conn is None:
            raise RuntimeError(f"no connection to run {sql} on (setup_own_db_access was not called)")
        cls._retry_deadlocks('B', what, lambda: cls._in_transaction(db_conn, sql))

    @classmethod
    def _count_deadlock(cls, stage: str) -> None:
        with cls._deadlocks_lock:
            cls._deadlocks[stage] += 1

    @staticmethod
    def _log_phase_summary(
        first_block: int, last_block: int, phase_times: dict[str, float], prefetched: float | None
    ) -> None:
        total = sum(phase_times.values())
        # prefetched: how long the background load of this batch's operations ran,
        # overlapped with the previous batch; not part of total.
        log.info(
            "[PHASE-SUMMARY] blocks=%d-%d total=%.3fs %s%s",
            first_block,
            last_block,
            total,
            _format_times(phase_times),
            '' if prefetched is None else f' prefetched={prefetched:.3f}',
        )

    @staticmethod
    def _in_transaction(db: Db, *statements: str | tuple[str, list[int]]) -> None:
        """Run the statements in one transaction on `db`, rolled back when one fails.

        A tuple is a statement and the list it takes as :post_ids.
        """
        db.query_no_return("START TRANSACTION")
        try:
            for statement in statements:
                if isinstance(statement, tuple):
                    db.query_no_return(statement[0], post_ids=statement[1])
                else:
                    db.query_no_return(statement)
            db.query_no_return("COMMIT")
        except Exception:
            with contextlib.suppress(Exception):
                db.query_no_return("ROLLBACK")
            raise

    @classmethod
    def _retry_deadlocks(cls, stage: str, what: str, run: Callable[[], _T]) -> _T:
        """Return run(), which runs its own transactions, run again when PostgreSQL aborts one as a deadlock (40P01)."""
        attempt = 1
        while True:
            try:
                return run()
            except psycopg2.extensions.TransactionRollbackError:
                cls._count_deadlock(stage)
                if attempt == cls._MAX_DEADLOCK_RETRIES:
                    log.error("%s deadlock persisted after %d attempts", what, attempt)
                    raise
                log.warning("%s deadlock detected (attempt %d/%d), retrying", what, attempt, cls._MAX_DEADLOCK_RETRIES)
                sleep(0.1 * attempt)
                attempt += 1

    @classmethod
    def _kill_if_at(cls, point: str, first_block: int | None) -> None:
        """Exit the process at once, as a crash would, at --test-pipeline-kill's point of the batch starting at first_block."""
        if first_block is not None and cls._kill_point == (point, first_block):
            log.warning("[PIPELINE-KILL] point=%s batch=%d: exiting", point, first_block)
            logging.shutdown()
            os._exit(1)

    @classmethod
    def _process_batch_posts(cls, db: Db, first_block: int) -> tuple[list[Row], bool]:
        """Run the posts phase of the massive batch starting at first_block in its own transaction.

        Returns the phase's result rows and whether the batch's post data flush has
        already committed. A replay of a batch whose posts phase committed reuses that
        phase's results instead of applying its comment ops a second time; the markers
        commit with the phase (save_batch_post_results) and with the flush
        (PostDataCache.flush), on the batch's _batch_queue row.
        """
        db.query_no_return("START TRANSACTION")
        try:
            applied = db.query_all(
                f"SELECT posts_applied, post_data_applied FROM {SCHEMA_NAME}._batch_queue "
                f"WHERE first_block = {first_block:d}"
            )
            posts_applied = bool(applied) and bool(applied[0]._mapping['posts_applied'])
            post_data_applied = bool(applied) and bool(applied[0]._mapping['post_data_applied'])
            if posts_applied:
                log.info("Replay: reusing the results of the batch's committed posts phase")
                post_results = db.query_all(f"SELECT * FROM {SCHEMA_NAME}.restore_batch_post_results({first_block:d})")
            else:
                post_results = db.query_all(
                    f"SELECT * FROM {SCHEMA_NAME}.process_posts_from_staging({Community.start_block})"
                )
                db.query_no_return(f"SELECT {SCHEMA_NAME}.save_batch_post_results({first_block:d})")
            db.query_no_return("COMMIT")
        except Exception:
            with contextlib.suppress(Exception):
                db.query_no_return("ROLLBACK")
            raise
        return post_results, post_data_applied

    @classmethod
    def process_live_block_sql(cls, first_block: int, last_block: int) -> None:
        """Process blocks in live sync using SQL functions (sequential, shared connection).

        All phases run sequentially on the shared connection (no parallelism)
        inside a single transaction — normally the one hive.app_next_iteration
        left open in SyncHiveDb._main_loop, which already contains the HAF
        context advancement. The final COMMIT below therefore makes the context
        pointer, the block's work, and last_completed_block durable atomically:
        a crash or connection loss at any point rolls all of them back together
        and app_next_iteration() returns the same range again (#336).

        After SQL processing, live-sync-specific post-processing is performed
        (children count, root_id, feed cache, periodic actions) — all within the
        same transaction boundary.
        """
        time_start = OPSM.start()
        db = DbAdapterHolder.common_block_processing_db()

        # Normally already inside the transaction opened for app_next_iteration;
        # open one only if called with the connection in autocommit state.
        if not db.is_trx_active():
            db.query_no_return("START TRANSACTION")

        # Phase 1: Load staging table
        db.query_no_return(f"SELECT {SCHEMA_NAME}.load_ops_staging({first_block}, {last_block})")

        # Phase 2: Account registration + community state ops (before posts)
        db.query_no_return(f"SELECT {SCHEMA_NAME}.process_accounts_from_staging({Community.start_block})")
        db.query_no_return(f"SELECT {SCHEMA_NAME}.process_community_from_staging({Community.start_block}, 1)")

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

        db.query_no_return(f"SELECT {SCHEMA_NAME}.process_reblogs_from_staging({last_block:d})")
        db.query_no_return(f"SELECT * FROM {SCHEMA_NAME}.process_follows_for_blocks({first_block}, {last_block})")
        db.query_no_return(f"SELECT {SCHEMA_NAME}.process_account_updates_from_staging()")
        db.query_no_return(f"SELECT {SCHEMA_NAME}.process_lastread_from_staging()")
        db.query_no_return(f"SELECT {SCHEMA_NAME}.process_post_counts_from_staging({first_block:d})")
        db.query_no_return(f"SELECT {SCHEMA_NAME}.process_payouts_from_staging({cls._last_safe_cashout_block})")
        db.query_no_return(f"SELECT {SCHEMA_NAME}.process_community_from_staging({Community.start_block}, 2)")

        # Phase 5: PostDataCache flush (uses beginTx/commitTx which are no-ops in live mode,
        # so it executes within this wrapping transaction)
        PostDataCache.flush()

        # Phase 6: Notifications (sequential)
        db.query_no_return(f"SELECT {SCHEMA_NAME}.flush_vote_notifications_for_blocks({first_block}, {last_block})")
        db.query_no_return(f"SELECT {SCHEMA_NAME}.flush_post_notifications_for_blocks({first_block}, {last_block})")
        db.query_no_return(f"SELECT {SCHEMA_NAME}.flush_follow_notifications_for_blocks({first_block}, {last_block})")
        db.query_no_return(f"SELECT {SCHEMA_NAME}.flush_reblog_notifications_for_blocks({first_block}, {last_block})")

        # Live sync post-processing (within transaction boundary)
        log.info("[PROCESS LIVE SQL] Tables updating in live synchronization")
        cls.on_live_blocks_processed(first_block, last_block)
        cls._periodic_actions_by_num(last_block)
        cls._reset_staging_tables_if_due(db, last_block - first_block + 1)

        # Commit the entire block atomically
        db.query_no_return("COMMIT")

        log.info(
            "[PROCESS LIVE SQL] blocks %d-%d in %.4fs",
            first_block,
            last_block,
            OPSM.stop(time_start),
        )

    @classmethod
    def _reset_staging_tables_if_due(cls, db: Db, blocks: int) -> None:
        """Truncate the staging tables after _STAGING_RESET_INTERVAL calls or _STAGING_RESET_BLOCKS blocks, whichever comes first.

        Runs in the caller's transaction, if one is open.
        """
        cls._calls_since_staging_reset += 1
        cls._blocks_since_staging_reset += blocks
        if (
            cls._calls_since_staging_reset < cls._STAGING_RESET_INTERVAL
            and cls._blocks_since_staging_reset < cls._STAGING_RESET_BLOCKS
        ):
            return
        db.query_no_return(f"SELECT {SCHEMA_NAME}.reset_staging_tables()")
        cls._calls_since_staging_reset = 0
        cls._blocks_since_staging_reset = 0

    @classmethod
    def _reset_stage_staging_tables_if_due(cls, db: Db, stage: str, blocks: int) -> None:
        """_reset_staging_tables_if_due for the tables of one stage (reset_stage_a/b_staging_tables), in its own transaction."""
        due = cls._since_stage_reset[stage]
        due[0] += 1
        due[1] += blocks
        if due[0] < cls._STAGING_RESET_INTERVAL and due[1] < cls._STAGING_RESET_BLOCKS:
            return
        cls._in_transaction(db, f"SELECT {SCHEMA_NAME}.reset_stage_{stage.lower()}_staging_tables()")
        due[0] = due[1] = 0

    @classmethod
    def _process_post_results_for_cache(cls, post_results: list[Row]) -> None:
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
                post_data = {
                    'title': op_body.get('title', '') or '',
                    'body': op_body.get('body', '') or '',
                    'json': op_body.get('json_metadata', '') or '',
                    'is_root': 'true' if not parent_author else 'false',
                }
            else:
                body = op_body.get('body')
                new_body = Posts._merge_post_body(id=post_id, new_body_def=body) if body else None
                new_title = op_body.get('title') if op_body.get('title') else None
                new_json = op_body.get('json_metadata') if op_body.get('json_metadata') else None
                post_data = {'title': new_title, 'body': new_body, 'json': new_json, 'is_root': 'false'}

            PostDataCache.add_data(post_id, post_data, is_new, r['block_num'])

    @classmethod
    def _process_votes_massive(cls, times: dict[str, float] | None = None) -> int:
        """Run the votes phase of a massive batch; return the number of hive_votes rows written.

        With more than one worker, the batch's rows are prepared (ids drawn in
        serial order) and committed on `Votes.db`, then upserted by the workers
        in parallel, each on its own connection and its own share of the
        hive_votes unique key. A deadlock retry re-runs every partition: one that
        already committed upserts the same rows again, which the num_changes /
        block_num replay guard turns into a no-op. The prepare's and the upserts'
        times go into `times` (votes_prepare, votes_upsert).
        """
        times = {} if times is None else times
        dbs = Votes.upsert_dbs()
        if len(dbs) == 1:
            return _timed(
                times,
                'votes_upsert',
                lambda: int(
                    cls._run_parallel_sql(
                        [(dbs[0], f"SELECT {SCHEMA_NAME}.process_votes_from_staging({cls._last_safe_cashout_block})")]
                    )[0]
                ),
            )

        _timed(
            times,
            'votes_prepare',
            lambda: cls._in_transaction(dbs[0], f"SELECT {SCHEMA_NAME}.prepare_votes_from_staging()"),
        )
        return _timed(
            times,
            'votes_upsert',
            lambda: sum(
                int(count)
                for count in cls._run_parallel_sql(
                    [
                        (db, f"SELECT {SCHEMA_NAME}.upsert_votes_partition({part}, {len(dbs)})")
                        for part, db in enumerate(dbs)
                    ]
                )
            ),
        )

    @classmethod
    def _process_payouts_massive(cls, last_safe_cashout_block: int) -> int:
        """Apply a massive batch's payouts; return the number of hive_posts rows updated.

        With more than one connection, each applies its own share of the batch's posts
        (process_payouts_from_staging's partitions), all at once. A deadlock retry re-runs
        every partition: one that already committed applies the same payouts again, which
        changes nothing.
        """
        dbs = Payouts.partition_dbs()
        if len(dbs) == 1:
            return int(
                cls._run_parallel_sql(
                    [(dbs[0], f"SELECT {SCHEMA_NAME}.process_payouts_from_staging({last_safe_cashout_block:d})")]
                )[0]
            )
        return sum(
            int(count)
            for count in cls._run_parallel_sql(
                [
                    (
                        db,
                        f"SELECT {SCHEMA_NAME}.process_payouts_from_staging"
                        f"({last_safe_cashout_block:d}, {part}, {len(dbs)})",
                    )
                    for part, db in enumerate(dbs)
                ]
            )
        )

    @staticmethod
    def _run_parallel_sql(tasks: list[tuple[Db | None, str]], max_retries: int = 3) -> list[Any]:
        """Run multiple SQL functions in parallel on separate DB connections.

        Each task is a (db_connection, sql_string) tuple. Each function runs
        in its own transaction on its own connection. Retries the whole set on
        deadlock (PostgreSQL error 40P01), a single task included. Returns each
        task's first result column (None when it returned no row), in task order.
        """

        def run_one(db_conn: Db | None, sql: str) -> Any:
            if db_conn is None:
                raise RuntimeError(f"no connection to run {sql} on (setup_own_db_access was not called)")
            db_conn.query_no_return("START TRANSACTION")
            try:
                rows = db_conn.query_all_raw(sql)
                db_conn.query_no_return("COMMIT")
            except Exception:
                with contextlib.suppress(Exception):
                    db_conn.query_no_return("ROLLBACK")
                raise
            return rows[0][0] if rows else None

        attempt = 1
        while True:
            try:
                with ThreadPoolExecutor(max_workers=len(tasks)) as pool:
                    futures = [pool.submit(run_one, db_conn, sql) for db_conn, sql in tasks]
                    return [f.result() for f in futures]
            except psycopg2.extensions.TransactionRollbackError:
                Blocks._count_deadlock('B')
                if attempt == max_retries:
                    log.error("Parallel SQL deadlock persisted after %d attempts", max_retries)
                    raise
                log.warning(
                    "Parallel SQL deadlock detected (attempt %d/%d), retrying",
                    attempt,
                    max_retries,
                )
                sleep(0.1 * attempt)
                attempt += 1

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
    def on_live_blocks_processed(first_block: int, last_block: int | None = None) -> None:
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
