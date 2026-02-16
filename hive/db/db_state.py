"""Hive db state manager. Check if schema loaded, massive synced, etc."""

# pylint: disable=too-many-lines

import logging
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from time import perf_counter
from typing import Optional

import sqlalchemy

from hive.conf import ONE_WEEK_IN_BLOCKS, REPTRACKER_SCHEMA_NAME, SCHEMA_NAME, SCHEMA_OWNER_NAME, SWAGGER_URL
from hive.db.adapter import Db
from hive.db.schema import build_metadata, perform_db_upgrade, setup, setup_runtime_code, teardown
from hive.indexer.auto_db_disposer import AutoDbDisposer
from hive.utils.communities_rank import update_communities_posts_and_rank
from hive.utils.misc import get_memory_amount
from hive.utils.payout_stats import PayoutStats
from hive.utils.stats import FinalOperationStatusManager as FOSM

log = logging.getLogger(__name__)


class DbState:
    """Manages database state: sync status, migrations, etc."""

    _db = None
    _admin_db = None  # Admin connection for privileged operations like ALTER SYSTEM

    # prop is true until massive sync complete
    _is_massive_sync = False
    _indexes_were_disabled = False
    _indexes_were_enabled = False
    _fk_were_disabled = False
    _fk_were_enabled = False
    _original_synchronous_commit_mode = None
    _original_fsync = None
    _original_full_page_writes = None
    _rshares_recalculated = False
    _wal_safety_disable_attempted = False  # Track if we already tried to disable WAL safety

    @classmethod
    def initialize(cls, enter_massive: bool, schema_upgrade: bool):
        """Perform startup database checks.

        1) Load schema if needed
        2) Run migrations if needed
        3) Check if massive sync has completed
        """

        log.info("Welcome to hive!")

        db_setup_owner = cls.db().impersonated_clone('setup_owner', SCHEMA_OWNER_NAME)

        # create db schema if needed
        if not cls._is_schema_loaded():
            log.info("Create db schema...")
            db_setup_admin = cls.db().clone('setup_admin')

            setup(admin_db=db_setup_admin, db=db_setup_owner)
            db_setup_admin.close()
        elif schema_upgrade is True:
            log.info("Attempting to perform db schema upgrade...")
            db_setup_admin = cls.db().clone('setup_admin')
            perform_db_upgrade(admin_db=db_setup_admin, db=db_setup_owner)
            db_setup_admin.close()
            log.info("Database schema upgrade finished")

        db_setup_owner.query_no_return(f"SET SEARCH_PATH TO {REPTRACKER_SCHEMA_NAME}")
        db_setup_owner.query_no_return(f"SET custom.swagger_url = '{SWAGGER_URL}'")
        setup_runtime_code(db=db_setup_owner)

        db_setup_owner.close()

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
    def admin_db(cls):
        """Get or create admin db connection for privileged operations.

        Created lazily to avoid being captured in active_connections_before snapshot.
        May return None if base db is not available.
        """
        if cls._admin_db is None and cls._db is not None:
            cls._admin_db = cls._db.clone('admin_for_sync')
        return cls._admin_db

    @classmethod
    def close_admin_db(cls):
        """Close admin db connection after massive sync completes."""
        if cls._admin_db:
            cls._admin_db.close()
            cls._admin_db = None

    @classmethod
    def set_massive_sync(cls, is_massive: bool):
        cls._is_massive_sync = is_massive

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
    def disableable_indexes(cls):
        to_locate = [
            'hive_feed_cache_block_num_idx',
            'hive_feed_cache_created_at_idx',
            'hive_feed_cache_post_id_idx',
            'hive_feed_cache_account_id_created_at_post_id_idx',
            'hive_posts_parent_id_id_idx',
            'hive_posts_depth_idx',
            'hive_posts_root_id_id_idx',
            'hive_posts_community_id_id_idx',
            'hive_posts_community_id_is_pinned_idx',
            'hive_posts_community_id_not_is_pinned_idx',
            'hive_posts_community_id_not_is_paidout_idx',
            'hive_posts_payout_at_idx',
            'hive_posts_sc_trend_id_idx',
            'hive_posts_sc_hot_id_idx',
            'hive_posts_block_num_created_idx',
            'hive_posts_payout_plus_pending_payout_id_idx',
            'hive_posts_category_id_payout_plus_pending_payout_depth_idx',
            'hive_posts_author_id_created_at_id_idx',
            'hive_posts_author_id_id_idx',
            'hive_posts_block_num_idx',
            'hive_posts_author_id_id_depth0_idx',
            'hive_votes_voter_id_last_update_idx',
            'hive_votes_block_num_idx',
            'hive_subscriptions_block_num_idx',
            'hive_subscriptions_community_idx',
            'hive_communities_block_num_idx',
            'hive_votes_post_id_voter_id_idx',
            'hive_votes_post_id_block_num_rshares_vote_is_effective_idx',
            'hive_notification_cache_block_num_idx',
            'hive_notification_cache_dst_score_idx',
            'follows_following_idx',
            'muted_following_idx',
            'blacklisted_following_idx',
            'follow_muted_following_idx',
            'follow_blacklisted_following_idx',
            'follows_block_num_idx',
            'muted_block_num_idx',
            'blacklisted_block_num_idx',
            'follow_muted_block_num_idx',
            'follow_blacklisted_block_num_idx',
            'hive_post_data_bm25_idx',
            'hive_accounts_haf_id_idx',
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
    def _disableable_indexes(cls):
        _indexes = cls.disableable_indexes()

        metadata = sqlalchemy.MetaData(schema=REPTRACKER_SCHEMA_NAME)
        rep = sqlalchemy.Table(
            'account_reputations',
            metadata,
            sqlalchemy.Column('reputation', sqlalchemy.BigInteger, nullable=False, server_default='0'),
        )

        idx_reputation_on_account_reputations = sqlalchemy.Index(
            'idx_reputation_on_account_reputations', rep.c.reputation
        )

        if rep not in _indexes:
            _indexes[rep] = []
        _indexes[rep].append(idx_reputation_on_account_reputations)

        return _indexes

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
    def ensure_off_synchronous_commit(cls):
        if cls._original_synchronous_commit_mode is not None:
            return

        """Disables non-critical indexes for faster sync, as well as foreign key constraints."""
        cls._original_synchronous_commit_mode = cls.db().query_one("SELECT current_setting('synchronous_commit');")
        cls.db().query_no_return("SET synchronous_commit = OFF;")

        log.info("[MASSIVE] SET synchronous_commit = OFF")

    @classmethod
    def ensure_on_synchronous_commit(cls):
        if cls._original_synchronous_commit_mode is None:
            return

        cls.db().query_no_return(f"SET synchronous_commit = {cls._original_synchronous_commit_mode}")
        cls._original_synchronous_commit_mode = None

        log.info("SET synchronous_commit = ON")

    @classmethod
    def disable_wal_safety_for_massive_sync(cls):
        """Disable WAL safety features during massive sync for better performance.

        This is safe because if massive sync is interrupted, the database is in an
        inconsistent state anyway and must be rebuilt from scratch.

        Original values are saved and restored after massive sync completes.
        Requires superuser privileges via admin_db; skipped gracefully if not available.
        """
        if cls._original_fsync is not None or cls._wal_safety_disable_attempted:
            return  # Already disabled or already attempted

        cls._wal_safety_disable_attempted = True
        admin = cls.admin_db()
        if admin is None:
            log.info("[MASSIVE] No admin connection available, skipping WAL safety optimization")
            return

        try:
            # Save original values (can read from any connection)
            cls._original_fsync = cls.db().query_one("SELECT current_setting('fsync')")
            cls._original_full_page_writes = cls.db().query_one("SELECT current_setting('full_page_writes')")

            log.info(
                f"[MASSIVE] Saving WAL safety settings: fsync={cls._original_fsync}, full_page_writes={cls._original_full_page_writes}"
            )
            # ALTER SYSTEM requires superuser and cannot run inside a transaction block
            admin.query_no_return_autocommit("ALTER SYSTEM SET fsync = 'off'")
            admin.query_no_return_autocommit("ALTER SYSTEM SET full_page_writes = 'off'")
            admin.query_no_return_autocommit("SELECT pg_reload_conf()")
            log.info("[MASSIVE] WAL safety features disabled (fsync=off, full_page_writes=off)")
        except Exception as e:
            # ALTER SYSTEM requires superuser privileges
            log.warning(f"[MASSIVE] Could not disable WAL safety features (requires superuser): {e}")
            cls._original_fsync = None
            cls._original_full_page_writes = None

    @classmethod
    def restore_wal_safety_after_massive_sync(cls):
        """Restore WAL safety features to their original values after massive sync."""
        if cls._original_fsync is None:
            return  # Nothing to restore

        admin = cls.admin_db()
        if admin is None:
            log.warning("[MASSIVE] No admin connection available, cannot restore WAL safety settings")
            return

        try:
            log.info(
                f"[MASSIVE] Restoring WAL safety settings: fsync={cls._original_fsync}, full_page_writes={cls._original_full_page_writes}"
            )
            admin.query_no_return_autocommit(f"ALTER SYSTEM SET fsync = '{cls._original_fsync}'")
            admin.query_no_return_autocommit(f"ALTER SYSTEM SET full_page_writes = '{cls._original_full_page_writes}'")
            admin.query_no_return_autocommit("SELECT pg_reload_conf()")
        except Exception as e:
            log.warning(f"[MASSIVE] Could not restore WAL safety features: {e}")
        cls._original_fsync = None
        cls._original_full_page_writes = None
        cls._wal_safety_disable_attempted = False  # Reset for next sync
        log.info("[MASSIVE] WAL safety features restored")

    @classmethod
    def ensure_indexes_are_disabled(cls):
        if cls._indexes_were_disabled:
            return

        # is_pre_process, drop, create
        cls.processing_indexes(True, True, False)

        # Set tables to UNLOGGED for faster inserts (no WAL writes)
        from hive.db.schema import set_logged_table_attribute

        set_logged_table_attribute(cls.db(), False)

        cls._indexes_were_disabled = True
        cls._indexes_were_enabled = False
        log.info("[MASSIVE] Indexes are disabled")

    @classmethod
    def ensure_fk_are_disabled(cls):
        if cls._fk_were_disabled:
            return

        log.info("Dropping foreign keys")
        from hive.db.schema import drop_fk

        time_start = perf_counter()
        drop_fk(cls.db())
        end_time = perf_counter()
        elapsed_time = end_time - time_start
        log.info("Dropped foreign keys: %.4f s", elapsed_time)
        if cls.db().is_trx_active():
            cls.db().query_no_return("COMMIT")

        cls._fk_were_disabled = True
        cls._fk_were_enabled = False

    @classmethod
    def are_indexes_enabled(cls):
        return cls._indexes_were_enabled

    @classmethod
    def ensure_indexes_are_enabled(cls):
        if cls.are_indexes_enabled():
            return

        start_time = perf_counter()

        # Set tables back to LOGGED before creating indexes
        # This must happen before index creation because some indexes (e.g., BM25/pg_search)
        # don't support UNLOGGED tables
        from hive.db.schema import set_logged_table_attribute

        set_logged_table_attribute(cls.db(), True)

        log.info("Creating indexes: started")
        cls.processing_indexes(False, False, True)
        log.info("Creating indexes: finished")

        cls._indexes_were_disabled = False
        cls._indexes_were_enabled = True
        log.info("Indexes are enabled")
        end_time = perf_counter()
        log.info("[MASSIVE] After massive sync actions done in %.4fs", end_time - start_time)

    @classmethod
    def ensure_fk_are_enabled(cls):
        if cls._fk_were_enabled:
            return

        # Note: set_logged_table_attribute(True) is now called in ensure_indexes_are_enabled()
        # because some indexes (e.g., BM25/pg_search) don't support UNLOGGED tables
        from hive.db.schema import create_fk

        start_time_foreign_keys = perf_counter()
        log.info("Recreating foreign keys")
        create_fk(cls.db())
        log.info(f"Foreign keys were recreated in {perf_counter() - start_time_foreign_keys:.3f}s")
        if cls.db().is_trx_active():
            cls.db().query_no_return("COMMIT")

        cls._fk_were_disabled = False
        cls._fk_were_enabled = True

    @classmethod
    def _finish_hive_posts(cls, db, massive_sync_preconditions, last_imported_block, current_imported_block):
        with AutoDbDisposer(db, "finish_hive_posts") as db_mgr:
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
            # Update root_id for all root posts (depth=0 posts have root_id temporarily set to 0 on INSERT)
            time_start = perf_counter()
            if massive_sync_preconditions:
                # Initial massive sync: update ALL root posts without block range restriction
                sql = f"SELECT {SCHEMA_NAME}.update_hive_posts_root_id(NULL, NULL);"
            else:
                sql = (
                    f"SELECT {SCHEMA_NAME}.update_hive_posts_root_id({last_imported_block}, {current_imported_block});"
                )
            cls._execute_query_with_modified_work_mem(db=db_mgr.db, sql=sql)
            log.info("[MASSIVE] update_hive_posts_root_id executed in %.4fs", perf_counter() - time_start)

            # Sanity check: no root posts should have root_id = 0 after finalization
            broken = db_mgr.db.query_one(
                f"SELECT COUNT(*) FROM {SCHEMA_NAME}.hive_posts WHERE root_id = 0 AND depth = 0 AND id != 0"
            )
            if broken:
                log.error("[MASSIVE] CRITICAL: %d root posts still have root_id = 0 after finalization!", broken)
                raise RuntimeError(f"Finalization failed: {broken} root posts have root_id = 0")

    @classmethod
    def _finish_hive_feed_cache(cls, db, last_imported_block, current_imported_block):
        with AutoDbDisposer(db, "finish_hive_feed_cache") as db_mgr:
            time_start = perf_counter()
            sql = f"SELECT {SCHEMA_NAME}.update_feed_cache({last_imported_block}, {current_imported_block});"
            cls._execute_query_with_modified_work_mem(db=db_mgr.db, sql=sql)
            log.info("[MASSIVE] update_feed_cache executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_payout_stats_view(cls, db):
        with AutoDbDisposer(db, "finish_payout_stats_view") as db_mgr:
            time_start = perf_counter()
            PayoutStats.generate(db=db_mgr.db)
            log.info("[MASSIVE] payout_stats_view executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_communities_posts_and_rank(cls, db):
        with AutoDbDisposer(db, "finish_communities_posts_and_rank") as db_mgr:
            time_start = perf_counter()
            update_communities_posts_and_rank(db_mgr.db)
            log.info("[MASSIVE] update_communities_posts_and_rank executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_muted_parents(cls, db):
        with AutoDbDisposer(db, "finish_muted_parents") as db_mgr:
            time_start = perf_counter()
            count = db_mgr.db.query_one(f"SELECT {SCHEMA_NAME}.propagate_all_muted_parents();")
            log.info(
                "[MASSIVE] propagate_all_muted_parents executed in %.4fs (%d posts updated)",
                perf_counter() - time_start,
                count or 0,
            )

    @classmethod
    def _finish_blocks_consistency_flag(cls, db, last_imported_block, current_imported_block):
        with AutoDbDisposer(db, "finish_blocks_consistency_flag") as db_mgr:
            time_start = perf_counter()
            # cls._execute_query_with_modified_work_mem(db=db_mgr.db, sql=sql)
            db_mgr.db.query_no_return(f"SELECT {SCHEMA_NAME}.update_last_completed_block({current_imported_block});")
            log.info("[MASSIVE] update_last_completed_block executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_posts_rshares(cls, db):
        with AutoDbDisposer(db, "finish_posts_rshares") as db_mgr:
            time_start = perf_counter()
            sql = f"SELECT {SCHEMA_NAME}.recalculate_all_posts_rshares();"
            db_mgr.db.query_no_return(sql)
            log.info("[MASSIVE] recalculate_all_posts_rshares executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_notification_cache(cls, db):
        with AutoDbDisposer(db, "finish_notification_cache") as db_mgr:
            time_start = perf_counter()
            sql = f"CALL {SCHEMA_NAME}.clear_muted_notifications();"
            cls._execute_query_with_modified_work_mem(db=db_mgr.db, sql=sql)
            log.info("[MASSIVE] clear_muted_notifications executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_vote_notifications(cls, db):
        """Flush vote notifications for the entire sync range at finalization.

        Vote notification scoring uses payout + pending_payout from hive_posts,
        which is only fully available after all payout virtual ops are processed.
        During massive sync batches, vote notifications are skipped because payout
        data for recent posts hasn't arrived yet (payouts come ~7 days after the post).
        At finalization, all payout data is available, so we flush all vote notifications.
        """
        with AutoDbDisposer(db, "finish_vote_notifications") as db_mgr:
            time_start = perf_counter()
            last_block = db_mgr.db.query_one("SELECT hive.app_get_current_block_num('hivemind_app')")
            sql = f"SELECT {SCHEMA_NAME}.flush_vote_notifications_for_blocks(1, {last_block})"
            result = db_mgr.db.query_one(sql)
            log.info(
                "[MASSIVE] flush_vote_notifications: %s notifications in %.4fs", result, perf_counter() - time_start
            )

    @classmethod
    def _finish_reputation_notification_scores(cls, db):
        """Recalculate reputation-based notification scores using final reputation data.

        During massive sync, post/follow/reblog notification scores are computed
        from reptracker_app.account_reputations at flush time. Since the reputation
        tracker runs concurrently, scores may reflect incomplete reputation data.
        This finalization step corrects them using the final values.
        """
        with AutoDbDisposer(db, "finish_reputation_notification_scores") as db_mgr:
            time_start = perf_counter()
            sql = f"""
                WITH log_account_rep AS (
                    SELECT account_id,
                        LOG(10, ABS(nullif(reputation, 0))) AS rep,
                        (CASE WHEN reputation < 0 THEN -1 ELSE 1 END) AS is_neg
                    FROM {REPTRACKER_SCHEMA_NAME}.account_reputations
                ),
                calculate_rep AS (
                    SELECT account_id, GREATEST(lar.rep - 9, 0) * lar.is_neg AS rep
                    FROM log_account_rep lar
                ),
                final_rep AS (
                    SELECT account_id, (cr.rep * 7.5 + 25)::INT AS rep FROM calculate_rep cr
                )
                UPDATE {SCHEMA_NAME}.hive_notification_cache hnc
                SET score = COALESCE(fr.rep, 25)
                FROM {SCHEMA_NAME}.hive_accounts ha
                JOIN final_rep fr ON ha.haf_id = fr.account_id
                WHERE hnc.src = ha.id
                    AND hnc.type_id IN (12, 13, 14, 15)
                    AND hnc.score != COALESCE(fr.rep, 25)
            """
            db_mgr.db.query_no_return(sql)
            log.info(
                "[MASSIVE] finish_reputation_notification_scores executed in %.4fs",
                perf_counter() - time_start,
            )

    @classmethod
    def time_collector(cls, func, args):
        startTime = FOSM.start()
        func(*args)
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
        log.info(f'{info} Real elapsed time: {perf_counter() - start_time:.3f}, completed threads: {completedThreads}')

    @classmethod
    def _finish_all_tables(cls, massive_sync_preconditions, last_imported_block, current_imported_block):
        start_time = FOSM.start()

        log.info("#############################################################################")

        if not cls._rshares_recalculated:
            # Run rshares recalculation first (creates ~54M dead tuples on hive_posts).
            # Must complete before Part 0 so update_all_hive_posts_children_count doesn't
            # scan a bloated table 256 times in a loop. Only needs to run once — subsequent
            # finalization cycles during catch-up have negligible new votes.
            cls._finish_posts_rshares(cls.db())

            # Vacuum hive_posts to clean dead tuples before Part 0 scans it
            cls.vacuum_tables_in_threads([f"{SCHEMA_NAME}.hive_posts"])
            cls._rshares_recalculated = True

        methods = [
            ('hive_feed_cache', cls._finish_hive_feed_cache, [cls.db(), last_imported_block, current_imported_block]),
            ('payout_stats_view', cls._finish_payout_stats_view, [cls.db()]),
            ('communities_posts_and_rank', cls._finish_communities_posts_and_rank, [cls.db()]),
            ('muted_parents', cls._finish_muted_parents, [cls.db()]),
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
            ('vote_notifications', cls._finish_vote_notifications, [cls.db()]),
        ]
        # Notifications are dependent on many tables, therefore it's necessary to calculate it at the end
        cls.process_tasks_in_threads("[MASSIVE] %i threads finished filling tables. Part nr 1", methods)

        # Recalculate reputation-based notification scores after all notifications are
        # flushed and muted ones cleared. Runs sequentially to avoid concurrent access
        # to hive_notification_cache with the tasks above.
        cls._finish_reputation_notification_scores(cls.db())

        real_time = FOSM.stop(start_time)

        log.info("=== FILLING FINAL DATA INTO TABLES ===")
        threads_time = FOSM.log_current("Total final operations time")
        log.info(
            f"Elapsed time: {real_time :.4f}s. Calculated elapsed time: {threads_time :.4f}s. Difference: {real_time - threads_time :.4f}s"
        )
        FOSM.clear()
        log.info("=== FILLING FINAL DATA INTO TABLES ===")

    @classmethod
    def vacuum_tables_in_threads(cls, tables):
        def vacuum_table(table, db):
            with AutoDbDisposer(db, "vacuum") as db_mgr:
                log.info(f"Vacuuming table {table}")
                if table == f"{SCHEMA_NAME}.hive_posts" or table == f"{SCHEMA_NAME}.hive_post_data":
                    db_mgr.db.get_connection(0).execute(sqlalchemy.text("VACUUM (FULL, VERBOSE,ANALYZE) " + table))
                else:
                    db_mgr.db.get_connection(0).execute(sqlalchemy.text("VACUUM (VERBOSE,ANALYZE) " + table))
                db_mgr.db.get_connection(0).execute(sqlalchemy.text("VACUUM (VERBOSE,ANALYZE) " + table))

        methods = []
        for table in tables:
            methods.append(('VACUUM ' + table, vacuum_table, [table, cls.db()]))

        cls.process_tasks_in_threads("Requesting vacuum on hivemind tables", methods)

    @classmethod
    def vacuum_all_hivemind_tables_in_threads(cls):
        log.info("Requesting vacuum on hivemind tables")
        sql = f"""
SELECT table_schema || '.' || table_name AS table_name
FROM information_schema.tables
WHERE table_schema = '{SCHEMA_NAME}' AND table_type = 'BASE TABLE'
"""
        rows = cls.db().query_all(sql)
        tables = []
        for row in rows:
            tables.append(row._mapping["table_name"])

        cls.vacuum_tables_in_threads(tables)

    @classmethod
    def ensure_finalize_massive_sync(cls, last_imported_blocks, last_completed_blocks):
        if last_imported_blocks > last_completed_blocks:
            if cls.db().is_trx_active():
                cls.db().query_no_return("COMMIT")

            is_initial_massive = (last_imported_blocks - last_completed_blocks) > ONE_WEEK_IN_BLOCKS

            if is_initial_massive:
                cls.vacuum_all_hivemind_tables_in_threads()

            cls._finish_all_tables(is_initial_massive, last_completed_blocks, last_imported_blocks)

            if is_initial_massive:
                cls.vacuum_tables_in_threads(
                    [
                        f"{SCHEMA_NAME}.hive_posts",
                        f"{SCHEMA_NAME}.hive_feed_cache",
                        f"{SCHEMA_NAME}.hive_mentions",
                        f"{SCHEMA_NAME}.hive_communities",
                        f"{SCHEMA_NAME}.hive_state",
                        f"{SCHEMA_NAME}.hive_notification_cache",
                        f"{SCHEMA_NAME}.hive_accounts",
                    ]
                )

            log.info("[MASSIVE] Massive sync complete!")
            return True
        return False

    @staticmethod
    def status():
        """Basic health status: head block/time, current age (secs)."""
        sql = f"SELECT * FROM {SCHEMA_NAME}.get_head_state()"
        row = DbState.db().query_row(sql)._mapping
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
        raise Exception(f"unknown db engine {_engine_name}")

    @classmethod
    def _is_feed_cache_empty(cls):
        """Check if the hive_feed_cache table is empty.

        If empty, it indicates that the massive sync has not finished.
        """
        return not cls.db().query_one(f"SELECT 1 FROM {SCHEMA_NAME}.hive_feed_cache LIMIT 1")
