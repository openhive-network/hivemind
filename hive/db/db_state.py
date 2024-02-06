"""Hive db state manager. Check if schema loaded, massive synced, etc."""

# pylint: disable=too-many-lines

from concurrent.futures import as_completed, ThreadPoolExecutor
import logging
import time
from time import perf_counter
from typing import Optional

import sqlalchemy

from hive.conf import (
   SCHEMA_NAME
  ,SCHEMA_OWNER_NAME
  )

from hive.db.adapter import Db
from hive.db.schema import build_metadata, setup, teardown
from hive.indexer.auto_db_disposer import AutoDbDisposer
from hive.server.common.payout_stats import PayoutStats
from hive.utils.communities_rank import update_communities_posts_and_rank
from hive.utils.misc import get_memory_amount
from hive.utils.stats import FinalOperationStatusManager as FOSM

log = logging.getLogger(__name__)

SYNCED_BLOCK_LIMIT = 7 * 24 * 1200  # 7 days


class DbState:
    """Manages database state: sync status, migrations, etc."""

    _db = None

    # prop is true until massive sync complete
    _is_massive_sync = True

    @classmethod
    def initialize(cls, enter_massive: bool):
        """Perform startup database checks.

        1) Load schema if needed
        2) Run migrations if needed
        3) Check if massive sync has completed
        """

        log.info("Welcome to hive!")

        # create db schema if needed
        if not cls._is_schema_loaded():
            log.info("Create db schema...")
            db_setup_admin = cls.db().clone('setup_admin')
            db_setup_owner = cls.db().impersonated_clone('setup_owner', SCHEMA_OWNER_NAME)
            setup(admin_db=db_setup_admin, db=db_setup_owner)
            db_setup_admin.close()
            db_setup_owner.close()

        # check if massive sync complete
        cls._is_massive_sync = enter_massive
        if enter_massive:
          log.info("[MASSIVE] Continue with massive sync...")

    @classmethod
    def teardown(cls):
        """Drop all tables in db."""
        teardown(cls.db())

    @classmethod
    def db(cls):
        """Get a db adapter instance."""
        if not cls._db:
            cls._db = Db.instance()
        return cls._db

    @classmethod
    def finish_massive_sync(cls, current_imported_block) -> None:
        """Set status to massive sync complete."""
        if not cls._is_massive_sync:
            return
        cls._after_massive_sync(current_imported_block)
        cls._is_massive_sync = False
        if hasattr(cls,'_original_synchronous_commit_mode'):
            cls.db().query_no_return(f"SET synchronous_commit = {cls._original_synchronous_commit_mode}")
        log.info("[MASSIVE] Massive sync complete!")

    @classmethod
    def is_massive_sync(cls):
        """Check if we're still in the process of massive sync."""
        return cls._is_massive_sync

    @classmethod
    def _all_foreign_keys(cls):
        md = build_metadata()
        out = []
        for table in md.tables.values():
            out.extend(table.foreign_keys)
        return out

    @classmethod
    def _disableable_indexes(cls):
        to_locate = [
            'hive_feed_cache_block_num_idx',
            'hive_feed_cache_created_at_idx',
            'hive_feed_cache_post_id_idx',
            'hive_feed_cache_account_id_created_at_post_id_idx',
            'hive_follows_following_state_idx',  # (following, state, created_at, follower)
            'hive_follows_follower_state_idx',  # (follower, state, created_at, following)
            'hive_follows_follower_following_state_idx',
            'hive_follows_block_num_idx',
            'hive_follows_created_at_idx',
            'hive_posts_parent_id_id_idx',
            'hive_posts_depth_idx',
            'hive_posts_root_id_id_idx',
            'hive_posts_community_id_id_idx',
            'hive_posts_community_id_is_pinned_idx',
            'hive_posts_community_id_not_is_pinned_idx',
            'hive_posts_community_id_not_is_paidout_idx',
            'hive_posts_payout_at_idx',
            'hive_posts_payout_idx',
            'hive_posts_promoted_id_idx',
            'hive_posts_sc_trend_id_idx',
            'hive_posts_sc_hot_id_idx',
            'hive_posts_block_num_idx',
            'hive_posts_block_num_created_idx',
            'hive_posts_cashout_time_id_idx',
            'hive_posts_updated_at_idx',
            'hive_posts_payout_plus_pending_payout_id_idx',
            'hive_posts_category_id_payout_plus_pending_payout_depth_idx',
            'hive_posts_tags_ids_idx',
            'hive_posts_author_id_created_at_id_idx',
            'hive_posts_author_id_id_idx',
            'hive_posts_api_helper_author_s_permlink_idx',
            'hive_votes_voter_id_last_update_idx',
            'hive_votes_block_num_idx',
            'hive_subscriptions_block_num_idx',
            'hive_subscriptions_community_idx',
            'hive_communities_block_num_idx',
            'hive_reblogs_created_at_idx',
            'hive_votes_voter_id_post_id_idx',
            'hive_votes_post_id_voter_id_idx',
            'hive_reputation_data_block_num_idx',
            'hive_notification_cache_block_num_idx',
            'hive_notification_cache_dst_score_idx',
        ]

        to_return = {}
        md = build_metadata()
        for table in md.tables.values():
            for index in table.indexes:
                if index.name not in to_locate:
                    continue
                to_locate.remove(index.name)
                if table not in to_return:
                    to_return[table] = []
                to_return[table].append(index)

        # ensure we found all the items we expected
        assert not to_locate, f"indexes not located: {to_locate}"
        return to_return

    @classmethod
    def has_index(cls, db, idx_name):
        sql = "SELECT count(*) FROM pg_class WHERE relname = :relname"
        count = db.query_one(sql, relname=idx_name)
        if count == 1:
            return True
        else:
            return False

    @classmethod
    def _execute_query(cls, db: Db, sql: str, explain: bool = False) -> None:
        time_start = perf_counter()

        log.info("[MASSIVE] Attempting to execute query: `%s'...", sql)

        db.explain().query_no_return(sql) if explain else db.query_no_return(sql)

        time_end = perf_counter()
        log.info("[MASSIVE] Query `%s' done in %.4fs", sql, time_end - time_start)

    @classmethod
    def _execute_query_with_modified_work_mem(
        cls, db: Db, sql: str, explain: bool = False, value: Optional[str] = None, separate_transaction: bool = True
    ) -> None:
        divide_factor = 64
        _value = value or f'{int(get_memory_amount() / divide_factor)}MB'

        sql_show_work_mem = 'SHOW work_mem;'
        work_mem_before = db.query_one(sql_show_work_mem)

        if separate_transaction:
            db.query('START TRANSACTION')

        db.query_no_return(sql='SET LOCAL work_mem = :work_mem', work_mem=_value)
        work_mem_local = db.query_one(sql_show_work_mem)

        message = f'SET work_mem was ineffective; given: {_value} before: {work_mem_before} now: {work_mem_local}'
        assert work_mem_local == _value, message

        cls._execute_query(db, sql, explain)

        if separate_transaction:
            db.query('COMMIT')

            work_mem_after = db.query_one(sql_show_work_mem)
            assert work_mem_after == work_mem_before, f'work_mem was changed: {work_mem_before} -> {work_mem_after}'

    @classmethod
    def processing_indexes_per_table(cls, db, table_name, indexes, is_pre_process, drop, create):
        log.info("[MASSIVE] Begin %s-massive sync hooks for table %s", "pre" if is_pre_process else "post", table_name)
        with AutoDbDisposer(db, table_name) as db_mgr:
            engine = db_mgr.db.engine()

            any_index_created = False

            for index in indexes:
                log.info("%s index %s.%s", ("Drop" if is_pre_process else "Recreate"), index.table, index.name)
                try:
                    if drop:
                        if cls.has_index(db_mgr.db, index.name):
                            time_start = perf_counter()
                            index.drop(engine)
                            end_time = perf_counter()
                            elapsed_time = end_time - time_start
                            log.info("Index %s dropped in time %.4f s", index.name, elapsed_time)
                except sqlalchemy.exc.ProgrammingError as ex:
                    log.warning(f"Ignoring ex: {ex}")

                if create:
                    if cls.has_index(db_mgr.db, index.name):
                        log.info("Index %s already exists... Creation skipped.", index.name)
                    else:
                        time_start = perf_counter()
                        index.create(engine)
                        end_time = perf_counter()
                        elapsed_time = end_time - time_start
                        log.info("Index %s created in time %.4f s", index.name, elapsed_time)
                        any_index_created = True

        log.info("[MASSIVE] End %s-massive sync hooks for table %s", "pre" if is_pre_process else "post", table_name)

    @classmethod
    def processing_indexes(cls, is_pre_process, drop, create):
        start_time = FOSM.start()
        action = 'CREATING' if create else 'DROPPING'
        _indexes = cls._disableable_indexes()

        methods = []
        for _key_table, indexes in _indexes.items():
            methods.append(
                (
                    _key_table.name,
                    cls.processing_indexes_per_table,
                    [cls.db(), _key_table.name, indexes, is_pre_process, drop, create],
                )
            )

        cls.process_tasks_in_threads("[MASSIVE] %i threads finished creating indexes.", methods)

        real_time = FOSM.stop(start_time)

        log.info(f"=== {action} INDEXES ===")
        threads_time = FOSM.log_current(f"Total {action} indexes time")
        log.info(
            f"Elapsed time: {real_time :.4f}s. Calculated elapsed time: {threads_time :.4f}s. Difference: {real_time - threads_time :.4f}s"
        )
        FOSM.clear()
        log.info(f"=== {action} INDEXES ===")

    @classmethod
    def before_massive_sync(cls, last_imported_block: int, hived_head_block: int):
        """Disables non-critical indexes for faster sync, as well as foreign key constraints."""
        cls._original_synchronous_commit_mode = cls.db().query_one("SELECT current_setting('synchronous_commit');")
        cls.db().query_no_return("SET synchronous_commit = OFF;")

        cls._is_massive_sync = True
        to_sync = hived_head_block - last_imported_block

        if to_sync < SYNCED_BLOCK_LIMIT:
            log.info("[MASSIVE] Skipping pre-massive sync hooks")
            return


        log.info("Dropping foreign keys")
        from hive.db.schema import drop_fk
        time_start = perf_counter()
        drop_fk(cls.db())
        end_time = perf_counter()
        elapsed_time = end_time - time_start
        log.info("Dropped foreign keys: %.4f s", elapsed_time)

        # is_pre_process, drop, create
        cls.processing_indexes(True, True, False)


        # intentionally disabled since it needs a lot of WAL disk space when switching back to LOGGED
        # set_logged_table_attribute(cls.db(), False)

        log.info("[MASSIVE] Finish pre-massive sync hooks")


    @classmethod
    def _finish_hive_posts(cls, db, massive_sync_preconditions, last_imported_block, current_imported_block):
        with AutoDbDisposer(db, "finish_hive_posts") as db_mgr:
            # UPDATE: `abs_rshares`, `vote_rshares`, `sc_hot`, ,`sc_trend`, `total_votes`, `net_votes`
            time_start = perf_counter()
            sql = f"SELECT {SCHEMA_NAME}.update_posts_rshares({last_imported_block}, {current_imported_block});"
            cls._execute_query_with_modified_work_mem(db=db_mgr.db, sql=sql, explain=True)
            log.info("[MASSIVE] update_posts_rshares executed in %.4fs", perf_counter() - time_start)

            time_start = perf_counter()

            # UPDATE: `children`
            if massive_sync_preconditions:
                # Update count of all child posts (what was hold during massive sync)
                cls._execute_query_with_modified_work_mem(
                    db=db_mgr.db, sql=f"SELECT {SCHEMA_NAME}.update_all_hive_posts_children_count()"
                )
            else:
                # Update count of child posts processed during partial sync (what was hold during massive sync)
                sql = f"SELECT {SCHEMA_NAME}.update_hive_posts_children_count({last_imported_block}, {current_imported_block})"
                cls._execute_query_with_modified_work_mem(db=db_mgr.db, sql=sql)
            log.info("[MASSIVE] update_hive_posts_children_count executed in %.4fs", perf_counter() - time_start)

            # UPDATE: `root_id`
            # Update root_id all root posts
            time_start = perf_counter()
            sql = f"SELECT {SCHEMA_NAME}.update_hive_posts_root_id({last_imported_block}, {current_imported_block});"
            cls._execute_query_with_modified_work_mem(db=db_mgr.db, sql=sql)
            log.info("[MASSIVE] update_hive_posts_root_id executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_hive_posts_api_helper(cls, db, last_imported_block, current_imported_block):
        with AutoDbDisposer(db, "finish_hive_posts_api_helper") as db_mgr:
            time_start = perf_counter()
            sql = f"SELECT {SCHEMA_NAME}.update_hive_posts_api_helper({last_imported_block}, {current_imported_block});"
            cls._execute_query_with_modified_work_mem(db=db_mgr.db, sql=sql)
            log.info("[MASSIVE] update_hive_posts_api_helper executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_hive_feed_cache(cls, db, last_imported_block, current_imported_block):
        with AutoDbDisposer(db, "finish_hive_feed_cache") as db_mgr:
            time_start = perf_counter()
            sql = f"SELECT {SCHEMA_NAME}.update_feed_cache({last_imported_block}, {current_imported_block});"
            cls._execute_query_with_modified_work_mem(db=db_mgr.db, sql=sql)
            log.info("[MASSIVE] update_feed_cache executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_hive_mentions(cls, db, last_imported_block, current_imported_block):
        with AutoDbDisposer(db, "finish_hive_mentions") as db_mgr:
            time_start = perf_counter()
            sql = f"SELECT {SCHEMA_NAME}.update_hive_posts_mentions({last_imported_block}, {current_imported_block});"
            cls._execute_query_with_modified_work_mem(db=db_mgr.db, sql=sql)
            log.info("[MASSIVE] update_hive_posts_mentions executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_payout_stats_view(cls):
        time_start = perf_counter()
        PayoutStats.generate()
        log.info("[MASSIVE] payout_stats_view executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_account_reputations(cls, db, last_imported_block, current_imported_block):
        log.info(
            f"Performing update_account_reputations on block range: {last_imported_block}:{current_imported_block}"
        )

        with AutoDbDisposer(db, "finish_account_reputations") as db_mgr:
            time_start = perf_counter()
            sql = f"SELECT {SCHEMA_NAME}.update_account_reputations({last_imported_block}, {current_imported_block}, True);"
            cls._execute_query_with_modified_work_mem(db=db_mgr.db, sql=sql)
            log.info("[MASSIVE] update_account_reputations executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_communities_posts_and_rank(cls, db):
        with AutoDbDisposer(db, "finish_communities_posts_and_rank") as db_mgr:
            time_start = perf_counter()
            update_communities_posts_and_rank(db_mgr.db)
            log.info("[MASSIVE] update_communities_posts_and_rank executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_blocks_consistency_flag(cls, db, last_imported_block, current_imported_block):
        with AutoDbDisposer(db, "finish_blocks_consistency_flag") as db_mgr:
            time_start = perf_counter()
            #cls._execute_query_with_modified_work_mem(db=db_mgr.db, sql=sql)
            db_mgr.db.query_no_return(f"SELECT {SCHEMA_NAME}.update_last_completed_block({current_imported_block});");
            db_mgr.db.query_no_return(f"SELECT hive.app_set_current_block_num('hivemind_app', {current_imported_block});");
            log.info("[MASSIVE] update_last_completed_block executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_notification_cache(cls, db):
        with AutoDbDisposer(db, "finish_notification_cache") as db_mgr:
            time_start = perf_counter()
            sql = f"SELECT {SCHEMA_NAME}.update_notification_cache(NULL, NULL, False);"
            cls._execute_query_with_modified_work_mem(db=db_mgr.db, sql=sql)
            log.info("[MASSIVE] update_notification_cache executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_follow_count(cls, db, last_imported_block, current_imported_block):
        with AutoDbDisposer(db, "finish_follow_count") as db_mgr:
            time_start = perf_counter()
            sql = f"SELECT {SCHEMA_NAME}.update_follow_count({last_imported_block}, {current_imported_block});"
            cls._execute_query_with_modified_work_mem(db=db_mgr.db, sql=sql)
            log.info("[MASSIVE] update_follow_count executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def time_collector(cls, func, args):
        startTime = FOSM.start()
        result = func(*args)
        return FOSM.stop(startTime)

    @classmethod
    def process_tasks_in_threads(cls, info, methods):
        start_time = perf_counter()
        futures = []
        pool = ThreadPoolExecutor(max_workers=Db.max_connections)
        futures = {
            pool.submit(cls.time_collector, method, args): (description) for (description, method, args) in methods
        }

        completedThreads = 0
        for future in as_completed(futures):
            description = futures[future]
            completedThreads = completedThreads + 1
            try:
                elapsedTime = future.result()
                FOSM.final_stat(description, elapsedTime)
            except Exception as exc:
                log.error(f'{description!r} generated an exception: {exc}')
                raise exc

        pool.shutdown()
        log.info(f'{info} Real elapsed time: {perf_counter() - start_time:.3f}', completedThreads)

    @classmethod
    def _finish_all_tables(cls, massive_sync_preconditions, last_imported_block, current_imported_block):
        start_time = FOSM.start()

        log.info("#############################################################################")

        methods = [
            ('hive_feed_cache', cls._finish_hive_feed_cache, [cls.db(), last_imported_block, current_imported_block]),
            ('hive_mentions', cls._finish_hive_mentions, [cls.db(), last_imported_block, current_imported_block]),
            ('payout_stats_view', cls._finish_payout_stats_view, []),
            ('communities_posts_and_rank', cls._finish_communities_posts_and_rank, [cls.db()]),
            (
                'hive_posts',
                cls._finish_hive_posts,
                [cls.db(), massive_sync_preconditions, last_imported_block, current_imported_block],
            ),
            (
                'blocks_consistency_flag',
                cls._finish_blocks_consistency_flag,
                [cls.db(), last_imported_block, current_imported_block],
            ),
        ]
        cls.process_tasks_in_threads("[MASSIVE] %i threads finished filling tables. Part nr 0", methods)

        methods = [
            ('notification_cache', cls._finish_notification_cache, [cls.db()]),
            ('follow_count', cls._finish_follow_count, [cls.db(), last_imported_block, current_imported_block]),
            (
                'hive_posts_api_helper',
                cls._finish_hive_posts_api_helper,
                [cls.db(), last_imported_block, current_imported_block],
            ),
        ]
        # Notifications are dependent on many tables, therefore it's necessary to calculate it at the end
        # hive_posts_api_helper is dependent on `hive_posts/root_id` filling
        cls.process_tasks_in_threads("[MASSIVE] %i threads finished filling tables. Part nr 1", methods)

        real_time = FOSM.stop(start_time)

        log.info("=== FILLING FINAL DATA INTO TABLES ===")
        threads_time = FOSM.log_current("Total final operations time")
        log.info(
            f"Elapsed time: {real_time :.4f}s. Calculated elapsed time: {threads_time :.4f}s. Difference: {real_time - threads_time :.4f}s"
        )
        FOSM.clear()
        log.info("=== FILLING FINAL DATA INTO TABLES ===")

    @classmethod
    def _after_massive_sync(cls, current_imported_block: int) -> None:
        """Re-creates non-core indexes for serving APIs after massive sync, as well as all foreign keys."""
        from hive.indexer.blocks import Blocks

        start_time = perf_counter()

        last_imported_block = Blocks.last_completed()

        log.info(
            "[MASSIVE] Current imported block: %s. Last imported block: %s.",
            current_imported_block,
            last_imported_block,
        )
        if last_imported_block > current_imported_block:
            last_imported_block = current_imported_block

        synced_blocks = current_imported_block - last_imported_block

        cls._finish_account_reputations(cls.db(), last_imported_block, current_imported_block)

        force_index_rebuild = False
        massive_sync_preconditions = False
        if synced_blocks >= SYNCED_BLOCK_LIMIT:
            force_index_rebuild = True
            massive_sync_preconditions = True

        # is_pre_process, drop, create
        log.info("Creating indexes: started")
        cls.processing_indexes(False, force_index_rebuild, True)
        log.info("Creating indexes: finished")

        # Update statistics and execution plans after index creation.
        if massive_sync_preconditions:
            cls._execute_query(db=cls.db(), sql="VACUUM (VERBOSE,ANALYZE)")

        # all post-updates are executed in different threads: one thread per one table
        log.info("Filling tables with final values: started")
        cls._finish_all_tables(massive_sync_preconditions, last_imported_block, current_imported_block)
        log.info("Filling tables with final values: finished")

        if massive_sync_preconditions:
            from hive.db.schema import create_fk

            # intentionally disabled since it needs a lot of WAL disk space when switching back to LOGGED
            # set_logged_table_attribute(cls.db(), True)
            start_time_foreign_keys = perf_counter()
            log.info("Recreating foreign keys")
            create_fk(cls.db())
            log.info(f"Foreign keys were recreated in {perf_counter() - start_time_foreign_keys:.3f}s")

            cls._execute_query(db=cls.db(), sql="VACUUM (VERBOSE,ANALYZE)")

        end_time = perf_counter()
        log.info("[MASSIVE] After massive sync actions done in %.4fs", end_time - start_time)

    @staticmethod
    def status():
        """Basic health status: head block/time, current age (secs)."""
        sql = f"SELECT * FROM {SCHEMA_NAME}.get_head_state()"
        row = DbState.db().query_row(sql)
        return dict(
            db_head_block=row['num'], db_head_time=str(row['created_at']), db_head_age=int(time.time() - row['age'])
        )

    @classmethod
    def _is_schema_loaded(cls):
        """Check if the schema has been loaded into db yet."""
        # check if database has been initialized (i.e. schema loaded)
        _engine_name = cls.db().engine_name()
        if _engine_name == 'postgresql':
            return bool(cls.db().query_one(f"SELECT 1 FROM pg_catalog.pg_tables WHERE schemaname = '{SCHEMA_NAME}';"))
        if _engine_name == 'mysql':
            return bool(cls.db().query_one('SHOW TABLES'))
        raise Exception(f"unknown db engine {_engine_name}")

    @classmethod
    def _is_feed_cache_empty(cls):
        """Check if the hive_feed_cache table is empty.

        If empty, it indicates that the massive sync has not finished.
        """
        return not cls.db().query_one(f"SELECT 1 FROM {SCHEMA_NAME}.hive_feed_cache LIMIT 1")
