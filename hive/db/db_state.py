"""Hive db state manager. Check if schema loaded, massive synced, etc."""

# pylint: disable=too-many-lines

import logging
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from time import perf_counter, sleep
from typing import Optional

import psycopg2.extensions

import hive.db.schema as schema_module
from hive.conf import (
    MASSIVE_WITHOUT_INDEXES_THRESHOLD_BLOCKS,
    REPTRACKER_SCHEMA_NAME,
    SCHEMA_NAME,
    SCHEMA_OWNER_NAME,
    SWAGGER_URL,
)
from hive.db.adapter import Db
from hive.db.schema import perform_db_upgrade, setup, setup_runtime_code, teardown
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
    _initial_sync = None  # Cached: True until the first finalization commits last_completed_block

    # Tables that have registered indexes (via register_indexes.sql)
    _TABLES_WITH_REGISTERED_INDEXES = [
        'hive_feed_cache',
        'hive_posts',
        'hive_votes',
        'hive_subscriptions',
        'hive_communities',
        'hive_notification_cache',
        'follows',
        'muted',
        'blacklisted',
        'follow_muted',
        'follow_blacklisted',
        'hive_accounts',
    ]

    # Tables with foreign key constraints
    _TABLES_WITH_FKS = [
        'hive_posts',
        'hive_votes',
        'hive_post_tags',
        'hive_reblogs',
        'hive_mentions',
    ]

    # Max retries for DDL operations that can deadlock with other HAF apps
    # (e.g. proxy-whitelist reading hivemind tables while hivemind drops FKs).
    _DDL_MAX_RETRIES = 5

    # During massive sync, autovacuum on the hot tables races the in-flight flush
    # statements' toast reads (missing/unexpected-chunk failures, #342), so it is
    # disabled on them and replaced by vacuums issued at chunk boundaries, when no
    # flush statement is running. Dead tuples on these tables come only from our
    # own batches, so a boundary check is at least as well-informed as autovacuum.
    # Values are dead-tuple counts that trigger a vacuum at the next boundary.
    MASSIVE_VACUUM_THRESHOLDS = {
        'hive_accounts': 50000,
        'hive_posts': 25000,
        'hive_post_tags': 50000,
        'hive_post_data': 50000,
    }

    @staticmethod
    def _retry_ddl(fn, description, max_retries=None):
        """Retry a DDL operation that may deadlock with other HAF apps.

        Other apps (proxy-whitelist, block explorer, etc.) may hold read locks
        on hivemind tables while hivemind needs AccessExclusiveLock for DDL
        (FK drop/restore, index drop/restore). These cross-app deadlocks are
        expected and transient — the other app's transaction will finish
        shortly.  The DDL operations are idempotent (already-dropped FKs are
        no-ops), so retrying is safe.
        """
        if max_retries is None:
            max_retries = DbState._DDL_MAX_RETRIES
        for attempt in range(1, max_retries + 1):
            try:
                fn()
                return
            except psycopg2.extensions.TransactionRollbackError:
                if attempt == max_retries:
                    log.error("DDL deadlock persisted after %d attempts: %s", max_retries, description)
                    raise
                log.warning(
                    "DDL deadlock on %s (attempt %d/%d), retrying after backoff",
                    description,
                    attempt,
                    max_retries,
                )
                sleep(1.0 * attempt)

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

        # Detect pg_search availability for existing DBs (setup() sets this for fresh installs)
        if not schema_module.pg_search_available:
            result = cls.db().query_all("SELECT COUNT(*) FROM pg_extension WHERE extname = 'pg_search'")
            if result and result[0][0] > 0:
                schema_module.pg_search_available = True
                log.info("pg_search extension detected in existing database")

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
    def _drop_all_registered_indexes(cls):
        """Drop all HAF-registered indexes for the hivemind_app context."""
        log.info("[MASSIVE] Dropping all registered indexes")
        time_start = perf_counter()
        cls._retry_ddl(
            lambda: cls.db().query_no_return("SELECT hive.app_save_and_drop_indexes('hivemind_app')"),
            "drop all registered indexes",
        )
        log.info("[MASSIVE] Dropped all registered indexes in %.4fs", perf_counter() - time_start)

    @classmethod
    def _restore_indexes_per_table(cls, db, full_table_name):
        """Restore indexes for a single table using HAF API. Runs in a thread."""
        with AutoDbDisposer(db, f'restore_idx_{full_table_name}') as db_mgr:
            log.info("[MASSIVE] Restoring indexes for %s", full_table_name)
            time_start = perf_counter()
            cls._retry_ddl(
                lambda: db_mgr.db.query_no_return(
                    f"SELECT hive.app_restore_indexes('hivemind_app', '{full_table_name}')"
                ),
                f"restore indexes on {full_table_name}",
            )
            log.info("[MASSIVE] Restored indexes for %s in %.4fs", full_table_name, perf_counter() - time_start)

    @classmethod
    def _restore_bm25_index(cls, db):
        """Create the BM25 index on hive_post_data directly.

        Not registered with HAF because pg_search leaves internal metadata
        (MetaPage) that prevents UNLOGGED conversion even after the index is
        dropped. Instead we manage this index manually: created here during
        the fills phase, dropped explicitly in ensure_indexes_are_disabled.

        Skipped when pg_search extension is not available.
        """
        from hive.db.schema import pg_search_available

        if not pg_search_available:
            log.info("[MASSIVE] Skipping BM25 index creation (pg_search not available)")
            return

        with AutoDbDisposer(db, 'restore_bm25') as db_mgr:
            log.info("[MASSIVE] Creating BM25 index (deferred from index phase)")
            time_start = perf_counter()
            db_mgr.db.query_no_return(
                f"CREATE INDEX IF NOT EXISTS hive_post_data_bm25_idx ON {SCHEMA_NAME}.hive_post_data "
                "USING bm25 (id, title, body) WITH (key_field = 'id', "
                "text_fields = '{\"title\": {\"record\": \"position\"}, \"body\": {\"record\": \"position\"}}') "
                f"WHERE {SCHEMA_NAME}.is_top_level_post(id)"
            )
            log.info("[MASSIVE] BM25 index created in %.4fs", perf_counter() - time_start)

    @classmethod
    def _drop_indexes_in_threads(cls):
        """Drop all registered indexes for the hivemind_app context in one call."""
        start_time = FOSM.start()
        cls._drop_all_registered_indexes()
        real_time = FOSM.stop(start_time)
        log.info("=== DROPPING INDEXES === (%.4fs)", real_time)
        FOSM.clear()

    @classmethod
    def _restore_indexes_in_threads(cls):
        """Restore all registered indexes in parallel across tables.

        Excludes hive_post_data — the BM25 index is deferred to the fills phase
        where it runs in parallel with other finalization work.
        """
        start_time = FOSM.start()

        methods = []
        for table in cls._TABLES_WITH_REGISTERED_INDEXES:
            full_name = f'{SCHEMA_NAME}.{table}'
            methods.append((table, cls._restore_indexes_per_table, [cls.db(), full_name]))
        # Include reptracker index
        methods.append(
            (
                'account_reputations',
                cls._restore_indexes_per_table,
                [cls.db(), f'{REPTRACKER_SCHEMA_NAME}.account_reputations'],
            )
        )

        cls.process_tasks_in_threads("[MASSIVE] %i threads finished creating indexes.", methods)

        real_time = FOSM.stop(start_time)
        log.info("=== CREATING INDEXES ===")
        threads_time = FOSM.log_current("Total CREATING indexes time")
        log.info(
            f"Elapsed time: {real_time:.4f}s. Calculated elapsed time: {threads_time:.4f}s. Difference: {real_time - threads_time:.4f}s"
        )
        FOSM.clear()
        log.info("=== CREATING INDEXES ===")

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

        if not cls.is_initial_sync():
            # fsync=off is only tolerable when a crash means rebuilding from
            # scratch anyway; on a database with committed state it risks real
            # corruption for a marginal gain (WAL waits are <=2% of processing
            # time per the #339 measurements).
            return

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
    def is_initial_sync(cls):
        """True until the first massive finalization commits last_completed_block_num.

        Gates the machinery that is only justified (and only safe) when the
        database holds no irreplaceable state yet: UNLOGGED conversion, BM25
        drop/rebuild, and WAL-safety disabling. Cached per process — a crash
        during initial sync restarts with last_completed still 0, so the gate
        re-engages correctly.
        """
        if cls._initial_sync is None:
            last_completed = cls.db().query_one(f"SELECT last_completed_block_num FROM {SCHEMA_NAME}.hive_state")
            cls._initial_sync = (last_completed or 0) == 0
        return cls._initial_sync

    @classmethod
    def ensure_indexes_are_disabled(cls):
        if cls._indexes_were_disabled:
            return

        cls._drop_indexes_in_threads()

        if cls.is_initial_sync():
            # UNLOGGED conversion (and the BM25 drop it requires) only pays for
            # itself on initial sync: the round-trip costs ~6,600s + ~1,860s BM25
            # rebuild on production-class hardware, while WAL waits are <=2% of
            # with-indexes processing time (measurements in #339). It is also
            # only *safe* here — a PostgreSQL crash truncates UNLOGGED tables,
            # acceptable solely when the data can be rebuilt from scratch.

            # Drop BM25 index explicitly (not HAF-managed due to pg_search MetaPage issue).
            # Must be dropped before UNLOGGED conversion. Safe on first run (IF EXISTS).
            cls.db().query_no_return("DROP INDEX IF EXISTS hivemind_app.hive_post_data_bm25_idx")

            # Set tables to UNLOGGED for faster inserts (no WAL writes)
            from hive.db.schema import set_logged_table_attribute

            set_logged_table_attribute(cls.db(), False)

        cls.disable_autovacuum_for_massive_sync()

        cls._indexes_were_disabled = True
        cls._indexes_were_enabled = False
        log.info("[MASSIVE] Indexes are disabled")

    @classmethod
    def ensure_fk_are_disabled(cls):
        if cls._fk_were_disabled:
            return

        log.info("Dropping foreign keys")
        time_start = perf_counter()
        for table in cls._TABLES_WITH_FKS:
            cls._retry_ddl(
                lambda t=table: cls.db().query_no_return(
                    f"SELECT hive.app_save_and_drop_foreign_keys('hivemind_app', '{SCHEMA_NAME}', '{t}')"
                ),
                f"drop FK on {table}",
            )
        log.info("Dropped foreign keys: %.4f s", perf_counter() - time_start)

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
        cls._restore_indexes_in_threads()
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

        start_time_foreign_keys = perf_counter()
        log.info("Recreating foreign keys")
        for table in cls._TABLES_WITH_FKS:
            full_name = f'{SCHEMA_NAME}.{table}'
            cls._retry_ddl(
                lambda fn=full_name: cls.db().query_no_return(
                    f"SELECT hive.app_restore_foreign_keys('hivemind_app', '{fn}')"
                ),
                f"restore FK on {table}",
            )
        log.info(f"Foreign keys were recreated in {perf_counter() - start_time_foreign_keys:.3f}s")

        cls._fk_were_disabled = False
        cls._fk_were_enabled = True

    @classmethod
    def _finish_hive_posts(cls, db, massive_sync_preconditions, last_imported_block, current_imported_block):
        with AutoDbDisposer(db, "finish_hive_posts") as db_mgr:
            # UPDATE: `children`
            # Only the initial-massive full recompute runs here: it is idempotent,
            # so it is safe to repeat if finalization is interrupted before the
            # completion marker commits. The ranged variant applies *deltas* and
            # must commit exactly once — it runs inside the completion-marker
            # transaction instead (_finalize_completion_marker).
            if massive_sync_preconditions:
                time_start = perf_counter()
                cls._execute_query_with_modified_work_mem(
                    db=db_mgr.db, sql=f"SELECT {SCHEMA_NAME}.update_all_hive_posts_children_count()"
                )
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
            PayoutStats.generate(db=db_mgr.db, separate_transaction=True)
            log.info("[MASSIVE] payout_stats_view executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_communities_posts_and_rank(cls, db):
        with AutoDbDisposer(db, "finish_communities_posts_and_rank") as db_mgr:
            time_start = perf_counter()
            db_mgr.db.query("START TRANSACTION")
            update_communities_posts_and_rank(db_mgr.db)
            db_mgr.db.query("COMMIT")
            log.info("[MASSIVE] update_communities_posts_and_rank executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_muted_parents(cls, db):
        with AutoDbDisposer(db, "finish_muted_parents") as db_mgr:
            time_start = perf_counter()
            db_mgr.db.query("START TRANSACTION")
            count = db_mgr.db.query_one(f"SELECT {SCHEMA_NAME}.propagate_all_muted_parents();")
            db_mgr.db.query("COMMIT")
            log.info(
                "[MASSIVE] propagate_all_muted_parents executed in %.4fs (%d posts updated)",
                perf_counter() - time_start,
                count or 0,
            )

    @classmethod
    def _finalize_completion_marker(cls, db, massive_sync_preconditions, last_imported_block, current_imported_block):
        """Commit the finalization completion marker — always the LAST write of finalization.

        last_completed_block_num asserts "derived tables are consistent through
        this block", so it must not become durable before the fills it certifies:
        a crash mid-finalization would otherwise permanently strand blocks whose
        fills rolled back, unrepairable because the restarted finalization
        derives its range from this very marker (#337, and the same invariant as
        #336 one layer down).

        Everything in one transaction on a dedicated connection:
        - the ranged children-count update (non-initial path only): it applies
          deltas rather than absolute values, so it must commit exactly once —
          binding it to the marker gives exactly-once across crash/restart.
          All other fill tasks are idempotent and simply re-run on resume.
        - the root_id sanity check: runs before the marker so a detected
          inconsistency aborts finalization with the marker unset and the next
          startup retries the full range.
        - update_last_completed_block itself.
        """
        with AutoDbDisposer(db, "finalize_completion_marker") as db_mgr:
            time_start = perf_counter()
            db_mgr.db.query("START TRANSACTION")
            try:
                if not massive_sync_preconditions:
                    # Update count of child posts processed during partial sync (what was held during massive sync)
                    sql = f"SELECT {SCHEMA_NAME}.update_hive_posts_children_count({last_imported_block}, {current_imported_block})"
                    cls._execute_query_with_modified_work_mem(db=db_mgr.db, sql=sql, separate_transaction=False)

                # Sanity check: no root posts should have root_id = 0 after finalization
                broken = db_mgr.db.query_one(
                    f"SELECT COUNT(*) FROM {SCHEMA_NAME}.hive_posts WHERE root_id = 0 AND depth = 0 AND id != 0"
                )
                if broken:
                    log.error("[MASSIVE] CRITICAL: %d root posts still have root_id = 0 after finalization!", broken)
                    raise RuntimeError(f"Finalization failed: {broken} root posts have root_id = 0")

                db_mgr.db.query_no_return(
                    f"SELECT {SCHEMA_NAME}.update_last_completed_block({current_imported_block});"
                )
                db_mgr.db.query("COMMIT")
            except Exception:
                try:
                    db_mgr.db.query("ROLLBACK")
                except Exception:
                    log.warning("Ignoring ROLLBACK failure while aborting finalization", exc_info=True)
                raise
            log.info("[MASSIVE] finalization completion marker committed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_posts_rshares(cls, db):
        with AutoDbDisposer(db, "finish_posts_rshares") as db_mgr:
            time_start = perf_counter()
            sql = f"SELECT {SCHEMA_NAME}.recalculate_all_posts_rshares();"
            cls._execute_query_with_modified_work_mem(db=db_mgr.db, sql=sql)
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
            db_mgr.db.query("START TRANSACTION")
            last_block = db_mgr.db.query_one("SELECT hive.app_get_current_block_num('hivemind_app')")
            sql = f"SELECT {SCHEMA_NAME}.flush_vote_notifications_for_blocks(1, {last_block})"
            result = db_mgr.db.query_one(sql)
            db_mgr.db.query("COMMIT")
            log.info(
                "[MASSIVE] flush_vote_notifications: %s notifications in %.4fs", result, perf_counter() - time_start
            )

    @classmethod
    def _finish_vote_notifications_ranged(cls, db, last_imported_block, current_imported_block):
        """Backfill vote notifications for the range a short massive catch-up covered.

        Massive batches skip vote notifications (scoring needs payout data), and
        only the initial-massive finalization ran the full backfill — so every
        catch-up below the initial threshold silently lost its range's vote
        notifications (#338). The flush is idempotent (ON CONFLICT DO NOTHING)
        and windowed to the 90-day notification horizon inside the SQL.
        """
        with AutoDbDisposer(db, "finish_vote_notifications_ranged") as db_mgr:
            time_start = perf_counter()
            db_mgr.db.query("START TRANSACTION")
            sql = (
                f"SELECT {SCHEMA_NAME}.flush_vote_notifications_for_blocks("
                f"{last_imported_block + 1}, {current_imported_block})"
            )
            result = db_mgr.db.query_one(sql)
            db_mgr.db.query("COMMIT")
            log.info(
                "[MASSIVE] flush_vote_notifications (%d..%d): %s notifications in %.4fs",
                last_imported_block + 1,
                current_imported_block,
                result,
                perf_counter() - time_start,
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
            cls._execute_query_with_modified_work_mem(db=db_mgr.db, sql=sql)
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
    def _interrupted(cls, phase):
        """True when a shutdown was requested; finalization stops at task boundaries.

        Safe at any boundary: the completion marker only commits at the very end
        (_finalize_completion_marker), so an interrupted finalization is retried
        with the same range on the next startup, and every task that may have
        already committed is idempotent under that re-run.
        """
        from hive.signals import can_continue_thread

        if can_continue_thread():
            return False
        log.warning(
            "[MASSIVE] Shutdown requested — stopping finalization before %s. "
            "The completion marker is not set; finalization will resume from the same range on next startup.",
            phase,
        )
        return True

    @classmethod
    def _finish_all_tables(cls, massive_sync_preconditions, last_imported_block, current_imported_block):
        """Fill derived tables after massive sync. Returns True when finalization completed.

        Ordering contract: all fill tasks run (idempotently re-runnable) BEFORE
        _finalize_completion_marker commits last_completed_block_num as the very
        last write. Never add a task after the marker, and never let a task
        commit the marker early — see #337 for the incident this prevents.
        """
        start_time = FOSM.start()

        log.info("#############################################################################")

        if cls._interrupted("rshares recalculation"):
            return False

        if massive_sync_preconditions and not cls._rshares_recalculated:
            # Run rshares recalculation first (creates ~54M dead tuples on hive_posts).
            # Must complete before Part 0 so update_all_hive_posts_children_count doesn't
            # scan a bloated table 256 times in a loop. Only needs to run once per initial
            # massive sync — small gaps on restart don't need full recalculation since live
            # sync updates rshares incrementally per block.
            cls._finish_posts_rshares(cls.db())

            # Vacuum hive_posts to clean dead tuples before Part 0 scans it
            cls.vacuum_tables_in_threads([f"{SCHEMA_NAME}.hive_posts"])
            cls._rshares_recalculated = True

        if cls._interrupted("Part 0 fills"):
            return False

        methods = [
            ('hive_feed_cache', cls._finish_hive_feed_cache, [cls.db(), last_imported_block, current_imported_block]),
            (
                'hive_posts',
                cls._finish_hive_posts,
                [cls.db(), massive_sync_preconditions, last_imported_block, current_imported_block],
            ),
        ]
        if massive_sync_preconditions:
            methods += [
                ('payout_stats_view', cls._finish_payout_stats_view, [cls.db()]),
                ('communities_posts_and_rank', cls._finish_communities_posts_and_rank, [cls.db()]),
                ('muted_parents', cls._finish_muted_parents, [cls.db()]),
            ]
        else:
            # The initial path backfills vote notifications in Part 1; short
            # catch-ups must backfill their own range or lose it forever (#338).
            methods.append(
                (
                    'vote_notifications',
                    cls._finish_vote_notifications_ranged,
                    [cls.db(), last_imported_block, current_imported_block],
                )
            )
        # BM25 index creation is deferred from the index phase to here, running in
        # parallel with the fills above. Takes ~31min but is hidden inside Part 0
        # which takes ~48min, eliminating it from the critical path.
        methods.append(('bm25_index', cls._restore_bm25_index, [cls.db()]))
        cls.process_tasks_in_threads("[MASSIVE] %i threads finished filling tables. Part nr 0", methods)

        if massive_sync_preconditions:
            if cls._interrupted("Part 1 notification fills"):
                return False

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

        if cls._interrupted("completion marker"):
            return False

        # The very last write: ranged children delta (non-initial), root_id sanity
        # check, and last_completed_block_num, atomically.
        cls._finalize_completion_marker(
            cls.db(), massive_sync_preconditions, last_imported_block, current_imported_block
        )

        real_time = FOSM.stop(start_time)

        log.info("=== FILLING FINAL DATA INTO TABLES ===")
        threads_time = FOSM.log_current("Total final operations time")
        log.info(
            f"Elapsed time: {real_time:.4f}s. Calculated elapsed time: {threads_time:.4f}s. Difference: {real_time - threads_time:.4f}s"
        )
        FOSM.clear()
        log.info("=== FILLING FINAL DATA INTO TABLES ===")
        return True

    @classmethod
    def disable_autovacuum_for_massive_sync(cls):
        """Hand vacuum scheduling of the hot tables over to boundary vacuums."""
        for table in cls.MASSIVE_VACUUM_THRESHOLDS:
            cls.db().query_no_return(
                f"ALTER TABLE {SCHEMA_NAME}.{table} SET (autovacuum_enabled = off, toast.autovacuum_enabled = off)"
            )
        log.info("[MASSIVE] Autovacuum disabled on %s; boundary vacuums take over", list(cls.MASSIVE_VACUUM_THRESHOLDS))

    @classmethod
    def restore_autovacuum_after_massive_sync(cls):
        for table in cls.MASSIVE_VACUUM_THRESHOLDS:
            cls.db().query_no_return(
                f"ALTER TABLE {SCHEMA_NAME}.{table} RESET (autovacuum_enabled, toast.autovacuum_enabled)"
            )
        log.info("[MASSIVE] Autovacuum reloptions restored on %s", list(cls.MASSIVE_VACUUM_THRESHOLDS))

    @classmethod
    def run_boundary_vacuums(cls):
        """Vacuum any watched table whose dead tuples exceed its threshold.

        Called between chunks with no flush statement in flight; plain VACUUM
        (visibility map limits it to recently-churned pages, and the heavy
        indexes are dropped during massive sync anyway).
        """
        names = ','.join(f"'{t}'" for t in cls.MASSIVE_VACUUM_THRESHOLDS)
        rows = cls.db().query_all(
            f"SELECT relname, n_dead_tup FROM pg_stat_user_tables WHERE schemaname = '{SCHEMA_NAME}' AND relname IN ({names})"
        )
        due = [
            row._mapping['relname']
            for row in rows
            if row._mapping['n_dead_tup'] >= cls.MASSIVE_VACUUM_THRESHOLDS[row._mapping['relname']]
        ]
        if not due:
            return []

        def vacuum_table(table, db):
            with AutoDbDisposer(db, "boundary_vacuum") as db_mgr:
                db_mgr.db.query_no_return_autocommit(f"VACUUM {SCHEMA_NAME}.{table}")

        methods = [('VACUUM ' + table, vacuum_table, [table, cls.db()]) for table in due]
        cls.process_tasks_in_threads("Boundary vacuum on hivemind tables", methods)
        return due

    @classmethod
    def vacuum_tables_in_threads(cls, tables):
        def vacuum_table(table, db):
            with AutoDbDisposer(db, "vacuum") as db_mgr:
                log.info(f"Vacuuming table {table}")
                if table == f"{SCHEMA_NAME}.hive_posts" or table == f"{SCHEMA_NAME}.hive_post_data":
                    db_mgr.db.query_no_return_autocommit("VACUUM (FULL, VERBOSE,ANALYZE) " + table)
                else:
                    db_mgr.db.query_no_return_autocommit("VACUUM (VERBOSE,ANALYZE) " + table)
                db_mgr.db.query_no_return_autocommit("VACUUM (VERBOSE,ANALYZE) " + table)

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

            # Idempotent on purpose: after a crash the process-local state is gone
            # but the reloptions persist, so always RESET them at finalization.
            cls.restore_autovacuum_after_massive_sync()

            is_initial_massive = (
                last_imported_blocks - last_completed_blocks
            ) > MASSIVE_WITHOUT_INDEXES_THRESHOLD_BLOCKS

            if is_initial_massive:
                cls.vacuum_all_hivemind_tables_in_threads()

            if not cls._finish_all_tables(is_initial_massive, last_completed_blocks, last_imported_blocks):
                # Interrupted by a shutdown request before the completion marker
                # was committed; the next startup re-runs finalization with the
                # same range. Skip the post-finalization vacuums.
                return True

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
        return bool(cls.db().query_one(f"SELECT 1 FROM pg_catalog.pg_tables WHERE schemaname = '{SCHEMA_NAME}';"))

    @classmethod
    def _is_feed_cache_empty(cls):
        """Check if the hive_feed_cache table is empty.

        If empty, it indicates that the massive sync has not finished.
        """
        return not cls.db().query_one(f"SELECT 1 FROM {SCHEMA_NAME}.hive_feed_cache LIMIT 1")
