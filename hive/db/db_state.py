"""Hive db state manager. Check if schema loaded, massive synced, etc."""

# pylint: disable=too-many-lines

import logging
import time
from collections.abc import Callable, Sequence
from concurrent.futures import Future, ThreadPoolExecutor, as_completed
from time import perf_counter, sleep
from typing import Any

import psycopg2.errors
import psycopg2.extensions

import hive.db.schema as schema_module
from hive.conf import (
    APP_NAME,
    MASSIVE_WITHOUT_INDEXES_THRESHOLD_BLOCKS,
    REPTRACKER_SCHEMA_NAME,
    SCHEMA_NAME,
    SCHEMA_OWNER_NAME,
    SWAGGER_URL,
)
from hive.db.adapter import Db
from hive.db.schema import (
    SEED_LAST_COMPLETED_BLOCK,
    bm25_index_sql,
    perform_db_upgrade,
    recorded_table_schema,
    search_status,
    setup,
    setup_runtime_code,
    table_schema_digest,
    teardown,
)
from hive.db.visibility import VisibilityWatch, log_coverage
from hive.indexer.auto_db_disposer import AutoDbDisposer
from hive.utils.communities_rank import update_communities_posts_and_rank
from hive.utils.misc import get_memory_amount
from hive.utils.payout_stats import PayoutStats
from hive.utils.stats import FinalOperationStatusManager as FOSM
from hive.version import GIT_REVISION

log = logging.getLogger(__name__)

_RUN_UPGRADE = (
    "run `hive upgrade_schema` (the docker image's `setup --upgrade-schema`), or `hive build_schema` (`setup`), "
    "which applies a pending table upgrade, before starting sync"
)


_SEARCH_REMEDY = (
    "replay hivemind on a HAF image that preloads pg_search, or apply the manual remedy "
    "in hivemind issue #488 (its 2026-11-16 description revision)"
)


class TableSchemaBehindError(Exception):
    """The database's tables are not at the schema this code reads and writes."""


class DbState:
    """Manages database state: sync status, migrations, etc."""

    _db: Db | None = None
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
    _wal_safety_disable_attempted = False  # Track if we already tried to disable WAL safety
    _initial_sync: bool | None = None  # Cached: True until the first finalization commits last_completed_block
    _deferred_index_tables: list[str] = []  # Tables whose registered indexes wait for finalization's recompute
    _visibility_watch: VisibilityWatch | None = None

    # Tables that have registered indexes (via register_indexes.sql)
    _TABLES_WITH_REGISTERED_INDEXES = [
        'hive_feed_cache',
        'hive_posts',
        'hive_replies',
        'hive_votes',
        'hive_subscriptions',
        'hive_communities',
        'hive_moderation_log',
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

    # Vacuums run at most this many at a time, each on a connection of its own; set
    # from --vacuum-workers. Not Db.max_connections: the server's slots are shared
    # with the other HAF apps.
    vacuum_workers = 4
    # Connections of finalization's range-split recompute, and parallel workers of the
    # sort that orders hive_votes by post; set from --finalization-workers.
    finalization_workers = 4
    _VACUUM_CONNECT_ATTEMPTS = 5
    _VACUUM_CONNECT_BACKOFF_SECONDS = 2.0
    _VISIBILITY_VACUUM_NAME = "visibility_vacuum"
    _REPTRACKER_POLL_SECONDS = 10.0
    _REPTRACKER_LOG_EVERY_POLLS = 6

    # Max retries for DDL operations that can deadlock with other HAF apps
    # (e.g. proxy-whitelist reading hivemind tables while hivemind drops FKs).
    _DDL_MAX_RETRIES = 5

    # A non-concurrent index build (PostgreSQL's own scan, which pg_search's
    # uses) reads hive_post_data with SnapshotAny and indexes, so detoasts, every
    # row version recently dead as of the xmin horizon at its start. Its own
    # snapshot is newer than that horizon whenever another transaction holds the
    # horizon back (e.g. a co-tenant's long index build), so once that
    # transaction ends, the build alone no longer keeps those versions' toast. Its ShareLock keeps VACUUM off the heap but not autovacuum off the
    # toast table, which is vacuumed as a relation of its own: that is what
    # removed the chunks a build then failed on with DataCorrupted (#492), so
    # toast autovacuum is off for the build. A dead version whose toast an
    # earlier vacuum removed (its heap and toast passes compute their horizons
    # separately, #450) fails the same way; a plain VACUUM prunes it, and the
    # build is retried once after it.
    _BM25_BUILD_ATTEMPTS = 2

    # During massive sync, autovacuum on hive_post_data races the flush
    # statement's toast reads of post bodies (missing/unexpected-chunk failures,
    # #342 — every observed hit was this table), so it is disabled there and
    # replaced by vacuums issued at chunk boundaries, when no flush statement is
    # running. Scope is deliberately this one table: the other hot tables have no
    # toast read path, and the 60-70M bed A/B measured their concurrent
    # autovacuums as free in wall time while boundary vacuums of them cost 9.5%
    # (563s of synchronous stalls). hive_post_data itself needed ~1 vacuum per
    # 10M blocks, so serializing it costs nothing.
    # Values are dead-tuple counts that trigger a vacuum at the next boundary.
    MASSIVE_VACUUM_THRESHOLDS = {
        'hive_post_data': 50000,
    }

    # Tables whose index restore an initial sync defers to finalization, after the
    # full recompute that rewrites most of their rows: with the indexes in place,
    # every new row version is inserted into each of them.
    _INDEX_RESTORE_DEFERRED_TABLES = ['hive_posts']

    # The registered index an initial sync rewrites hive_votes in the order of, before
    # restoring the table's other indexes. Massive sync appends votes in block order,
    # which leaves a post's votes about a heap page apart each, and reading a post's
    # votes was the API's largest source of heap reads. Votes older than about a week
    # no longer change, so the order outlives the sync.
    _VOTES_ORDER_INDEX = 'hive_votes_post_id_voter_id_idx'
    # The UNLOGGED table hive_votes is sorted into and copied back from, inside the
    # transaction of the rewrite (_rewrite_hive_votes_in_post_order).
    _VOTES_SORTED_COPY = '__hive_votes_sorted'

    # The full recompute splits the post ids into this many ranges per connection, so
    # that a connection finishing a sparse range early takes another.
    _RECOMPUTE_RANGES_PER_WORKER = 4
    _MAX_POST_ID = 2**31 - 1

    # Tables finalization (_finish_all_tables) writes; frozen by the vacuum after it.
    _FINALIZATION_WRITTEN_TABLES = [
        'hive_posts',
        'hive_feed_cache',
        'hive_mentions',
        'hive_communities',
        'hive_state',
        'hive_notification_cache',
        'hive_accounts',
    ]

    @staticmethod
    def _retry_ddl(fn: Callable[..., Any], description: str, max_retries: int | None = None) -> None:
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
    def initialize(cls, enter_massive: bool, schema_upgrade: bool) -> None:
        """Perform startup database checks.

        1) Load schema if needed
        2) Run migrations if needed
        3) Check if massive sync has completed
        """

        log.info("Welcome to hive!")

        schema_loaded = cls._is_schema_loaded()
        table_schema_current = schema_loaded and cls._is_table_schema_current()
        if enter_massive and schema_loaded and not table_schema_current:
            raise TableSchemaBehindError(f"{cls._table_schema_behind_reason()}; {_RUN_UPGRADE}")

        db_setup_owner = cls.db().impersonated_clone('setup_owner', SCHEMA_OWNER_NAME)

        # create db schema if needed
        if not schema_loaded:
            log.info("Create db schema...")
            db_setup_admin = cls.db().clone('setup_admin')

            setup(admin_db=db_setup_admin, db=db_setup_owner)
            db_setup_admin.close()
        elif schema_upgrade is True or not table_schema_current:
            if not schema_upgrade:
                log.warning("%s; applying the table upgrade", cls._table_schema_behind_reason())
            log.info("Attempting to perform db schema upgrade...")
            db_setup_admin = cls.db().clone('setup_admin')
            perform_db_upgrade(admin_db=db_setup_admin, db=db_setup_owner)
            db_setup_admin.close()
            log.info("Database schema upgrade finished")

        cls._log_search_status()

        db_setup_owner.query_no_return(f"SET SEARCH_PATH TO {REPTRACKER_SCHEMA_NAME}")
        db_setup_owner.query_no_return(f"SET custom.swagger_url = '{SWAGGER_URL}'")
        setup_runtime_code(db=db_setup_owner)

        db_setup_owner.close()

    @classmethod
    def _log_search_status(cls) -> None:
        """Log, in one line, whether full-text search works and, when it does not, why and what to do."""
        status = search_status(cls.db())
        schema_module.pg_search_available = status.usable
        off = "full-text search (find_text, find_similar) is off"
        if not status.package_available:
            log.warning("%s: this PostgreSQL server has no pg_search package; %s", off, _SEARCH_REMEDY)
        elif not status.preloaded:
            log.warning("%s: pg_search is not in shared_preload_libraries; %s", off, _SEARCH_REMEDY)
        elif not status.extension_installed:
            log.warning("%s: the pg_search extension is not installed in this database; %s", off, _SEARCH_REMEDY)
        elif not status.function_present:
            log.warning("%s: %s.is_top_level_post is missing; %s", off, SCHEMA_NAME, _SEARCH_REMEDY)
        elif not status.index_present:
            if cls.is_initial_sync():
                log.info("Full-text search index hive_post_data_bm25_idx will be built at the end of the initial sync")
            else:
                log.warning("%s: the index hive_post_data_bm25_idx is missing; %s", off, _SEARCH_REMEDY)
        elif not status.index_valid:
            log.warning("%s: the index hive_post_data_bm25_idx is INVALID; %s", off, _SEARCH_REMEDY)
        else:
            log.info("Full-text search is ready (pg_search with a valid hive_post_data_bm25_idx)")

    @classmethod
    def _is_table_schema_current(cls) -> bool:
        return recorded_table_schema(cls.db()) == table_schema_digest()

    @classmethod
    def _table_schema_behind_reason(cls) -> str:
        recorded = recorded_table_schema(cls.db())
        return (
            f"hivemind's table schema is behind this code: the database records table upgrade "
            f"{recorded[:12] if recorded else 'none'}, this code's is {table_schema_digest()[:12]}"
        )

    @classmethod
    def pending_install_work(cls) -> list[str]:
        """What an install (build_schema / upgrade_schema) would change in the database; empty when nothing."""
        if not cls._is_schema_loaded():
            return ["the hivemind schema is not installed"]
        pending = []
        if not cls._is_table_schema_current():
            pending.append(cls._table_schema_behind_reason())
        runtime_revision = cls.db().query_one(f"SELECT hivemind_git_rev FROM {SCHEMA_NAME}.hive_state")
        if runtime_revision != GIT_REVISION:
            pending.append(f"the runtime code is of revision {runtime_revision}, this code is {GIT_REVISION}")
        return pending

    @classmethod
    def install_lock_holders(cls, app_name: str) -> str:
        """The sessions holding `app_name`'s HAF application or installer lock, as HAF's lock NOTICEs name them."""
        holders = cls.db().query_one(
            "SELECT string_agg(format('%%s (pid=%%s)', a.application_name, a.pid), ', ' ORDER BY a.pid) "
            "FROM pg_locks l JOIN pg_stat_activity a ON a.pid = l.pid "
            "WHERE l.locktype = 'advisory' AND l.granted AND l.pid <> pg_backend_pid() "
            "AND l.objid = hashtext(:app_name) "
            "AND l.classid IN (hashtext('hive_fork_manager_app_lock'), hashtext('hive_fork_manager_app_installer_lock'))",
            app_name=app_name,
        )
        return holders or '(unknown: released since)'

    @classmethod
    def _ensure_tables_exist(cls, tables: Sequence[str]) -> None:
        """Raise TableSchemaBehindError naming those of `tables` that are not in the database."""
        missing = cls.db().query_col(
            "SELECT t FROM unnest(CAST(:tables AS TEXT[])) t WHERE to_regclass(:schema || '.' || t) IS NULL",
            tables=list(tables),
            schema=SCHEMA_NAME,
        )
        if missing:
            names = ', '.join(f'{SCHEMA_NAME}.{t}' for t in missing)
            raise TableSchemaBehindError(f"hivemind's table schema is behind this code: no {names}; {_RUN_UPGRADE}")

    @classmethod
    def teardown(cls) -> None:
        """Drop all tables in db."""
        teardown(cls.db())

    @classmethod
    def db(cls) -> Db:
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
    def close_admin_db(cls) -> None:
        """Close admin db connection after massive sync completes."""
        if cls._admin_db:
            cls._admin_db.close()
            cls._admin_db = None

    @classmethod
    def set_massive_sync(cls, is_massive: bool) -> None:
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
        cls, db: Db, sql: str, explain: bool = False, value: str | None = None, separate_transaction: bool = True
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
    def _drop_all_registered_indexes(cls) -> None:
        """Drop all HAF-registered indexes for the hivemind_app context."""
        log.info("[MASSIVE] Dropping all registered indexes")
        time_start = perf_counter()
        cls._retry_ddl(
            lambda: cls.db().query_no_return("SELECT hive.app_save_and_drop_indexes('hivemind_app')"),
            "drop all registered indexes",
        )
        log.info("[MASSIVE] Dropped all registered indexes in %.4fs", perf_counter() - time_start)

    @classmethod
    def _restore_indexes_per_table(cls, db, full_table_name) -> None:
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
    def _order_hive_votes_by_post(cls, db: Db) -> bool:
        """Rewrite hive_votes in (post_id, voter_id) order; False when it is ordered already or cannot be.

        Everything happens in one transaction (_rewrite_hive_votes_in_post_order),
        which ends by marking the registered _VOTES_ORDER_INDEX as the table's
        clustering index, as CLUSTER would. The mark (pg_index.indisclustered) is
        how a rerun after a crash knows the rewrite is done: an interruption before
        the commit leaves neither the rewrite nor the mark. An index drop of massive
        sync clears the mark.
        """
        table = f'{SCHEMA_NAME}.hive_votes'
        with AutoDbDisposer(db, 'order_hive_votes') as db_mgr:
            row = db_mgr.db.query_row(
                f"""
SELECT ic.command, COALESCE(i.indisclustered, FALSE) AS clustered
FROM hafd.indexes_constraints ic
LEFT JOIN pg_index i ON i.indexrelid = to_regclass('{SCHEMA_NAME}.{cls._VOTES_ORDER_INDEX}')
WHERE ic.table_name = '{table}' AND ic.index_constraint_name = '{cls._VOTES_ORDER_INDEX}'
"""
            )
            if row is None:
                log.warning("[MASSIVE] %s is not registered; %s left in insertion order", cls._VOTES_ORDER_INDEX, table)
                return False
            if row._mapping['clustered']:
                log.info("[MASSIVE] %s already ordered by %s", table, cls._VOTES_ORDER_INDEX)
                return False

            log.info(
                "[MASSIVE] Ordering %s by %s, sorting with %d parallel workers",
                table,
                cls._VOTES_ORDER_INDEX,
                cls.finalization_workers,
            )
            time_start = perf_counter()
            timings: list[float] = []
            cls._retry_ddl(
                lambda: timings.extend(cls._rewrite_hive_votes_in_post_order(db_mgr.db, row._mapping['command'])),
                f"order {table}",
            )
            sort_time, copy_time, rebuild_time, order_index_time = timings
            log.info(
                "[MASSIVE] Ordered %s by post_id in %.4fs (parallel sort %.4fs, copy-back %.4fs, "
                "index and constraint rebuild %.4fs, %s %.4fs)",
                table,
                perf_counter() - time_start,
                sort_time,
                copy_time,
                rebuild_time,
                cls._VOTES_ORDER_INDEX,
                order_index_time,
            )
            return True

    @classmethod
    def _rewrite_hive_votes_in_post_order(cls, db: Db, order_index_command: str) -> list[float]:
        """Sort hive_votes into a copy, copy it back and mark the order, in one transaction; return the steps' seconds.

        CLUSTER sorts on one process; here a parallel query sorts the table into an
        UNLOGGED copy, on up to finalization_workers workers, and
        copy_back_hive_votes replaces the table's rows by the copy's and rebuilds
        its indexes. The order index is then built from its registered command
        (CREATE INDEX IF NOT EXISTS, so the restore that follows keeps it), marked
        as the clustering index, and the copy is dropped. The ACCESS EXCLUSIVE lock
        CLUSTER would hold is taken first, so that no lock is upgraded midway.
        Returns the seconds of the sort, the copy-back, the rebuild and the order
        index, in that order.
        """
        table = f'{SCHEMA_NAME}.hive_votes'
        copy = f'{SCHEMA_NAME}.{cls._VOTES_SORTED_COPY}'
        db.query_no_return("START TRANSACTION")
        try:
            db.query_no_return(f"LOCK TABLE {table} IN ACCESS EXCLUSIVE MODE")
            db.query_no_return(f"SET LOCAL max_parallel_workers_per_gather = {cls.finalization_workers}")
            # An index on (post_id, voter_id) left by an earlier hivemind would be read in
            # its order, with a heap page fetched per vote.
            db.query_no_return("SET LOCAL enable_indexscan = off")
            time_start = perf_counter()
            cls._execute_query_with_modified_work_mem(
                db=db,
                sql=f"CREATE UNLOGGED TABLE {copy} AS SELECT * FROM {table} ORDER BY post_id, voter_id",
                separate_transaction=False,
            )
            sort_time = perf_counter() - time_start
            copied = db.query_all(f"SELECT * FROM {SCHEMA_NAME}.copy_back_hive_votes('{copy}')")[0]._mapping
            time_start = perf_counter()
            db.query_no_return(order_index_command)
            db.query_no_return(f"ALTER TABLE {table} CLUSTER ON {cls._VOTES_ORDER_INDEX}")
            db.query_no_return(f"DROP TABLE {copy}")
            order_index_time = perf_counter() - time_start
            db.query_no_return("COMMIT")
        except BaseException:
            try:
                db.query_no_return("ROLLBACK")
            except psycopg2.Error:
                log.warning("Ignoring ROLLBACK failure while aborting the ordering of %s", table, exc_info=True)
            raise
        return [sort_time, copied['copy_seconds'], copied['rebuild_seconds'], order_index_time]

    @classmethod
    def _vacuum_ordered_hive_votes(cls, db: Db, search_index_built: Future[None]) -> None:
        """VACUUM (FREEZE, ANALYZE) hive_votes after its rewrite, once `search_index_built` is resolved.

        The rewritten rows carry the rewrite's transaction id. A BM25 build started
        before the rewrite committed holds the xmin horizon below that id until it
        ends, and a vacuum beside it could neither freeze those rows nor mark their
        pages all-visible. The vacuum sets the visibility map the rewrite left
        empty; when other apps' snapshots keep it from doing so, the
        VisibilityWatch of live sync finishes it.
        """
        table = f'{SCHEMA_NAME}.hive_votes'
        time_start = perf_counter()
        search_index_built.exception()
        wait_time = perf_counter() - time_start
        cls._run_vacuum(db, "order_vacuum", f"VACUUM (FREEZE, ANALYZE) {table}")
        vacuum_time = perf_counter() - time_start - wait_time
        with AutoDbDisposer(db, 'order_hive_votes_visibility') as db_mgr:
            visibility = db_mgr.db.query_row(
                f"SELECT relpages, relallvisible FROM pg_class WHERE oid = '{table}'::regclass"
            )._mapping
        log.info(
            "[MASSIVE] Vacuumed %s after its ordering in %.4fs, after waiting %.4fs for the BM25 build; "
            "%s of %s pages all-visible",
            table,
            vacuum_time,
            wait_time,
            visibility['relallvisible'],
            visibility['relpages'],
        )

    @classmethod
    def _order_and_restore_hive_votes(cls, db: Db, full_table_name: str, search_index_built: Future[None]) -> None:
        """Order hive_votes by post, restore its indexes, then vacuum it if it was rewritten."""
        ordered = cls._order_hive_votes_by_post(db)
        cls._restore_indexes_per_table(db, full_table_name)
        if ordered:
            cls._vacuum_ordered_hive_votes(db, search_index_built)

    @classmethod
    def _restore_bm25_index(cls, db) -> None:
        """Create the BM25 index on hive_post_data directly.

        Not registered with HAF because pg_search left internal metadata
        (MetaPage) that prevented the UNLOGGED conversion older versions did,
        even after the index was dropped. Instead we manage this index manually:
        created here, in an initial sync's last index restore or else during the
        fills phase, dropped explicitly in ensure_indexes_are_disabled.

        Skipped when pg_search extension is not available or the index exists.
        """
        from hive.db.schema import pg_search_available

        if not pg_search_available:
            log.info("[MASSIVE] Skipping BM25 index creation (pg_search not available)")
            return

        table = f"{SCHEMA_NAME}.hive_post_data"
        with AutoDbDisposer(db, 'restore_bm25') as db_mgr:
            if db_mgr.db.query_one(f"SELECT to_regclass('{SCHEMA_NAME}.hive_post_data_bm25_idx') IS NOT NULL"):
                log.info("[MASSIVE] BM25 index already exists")
                return
            # Taking the toast table's ShareUpdateExclusiveLock cancels a toast
            # autovacuum already running; none starts again until the RESET.
            # A crash in between leaves the option set, and the next start's
            # finalization RESETs it (restore_autovacuum_after_massive_sync).
            db_mgr.db.query_no_return(f"ALTER TABLE {table} SET (toast.autovacuum_enabled = off)")
            try:
                cls._build_bm25_index(db, db_mgr.db, table)
            finally:
                db_mgr.db.query_no_return(f"ALTER TABLE {table} RESET (toast.autovacuum_enabled)")

    @classmethod
    def _build_bm25_index(cls, db: Db, build_db: Db, table: str) -> None:
        for attempt in range(1, cls._BM25_BUILD_ATTEMPTS + 1):
            log.info("[MASSIVE] Creating BM25 index")
            time_start = perf_counter()
            try:
                build_db.query_no_return(bm25_index_sql())
            except psycopg2.errors.DataCorrupted as exc:
                if attempt == cls._BM25_BUILD_ATTEMPTS:
                    log.error("[MASSIVE] BM25 index build failed again after a vacuum of %s: %s", table, exc)
                    raise
                log.warning(
                    "[MASSIVE] BM25 index build hit a toast-chunk error after %.4fs (attempt %d/%d): %s; "
                    "falling back to vacuuming %s and retrying",
                    perf_counter() - time_start,
                    attempt,
                    cls._BM25_BUILD_ATTEMPTS,
                    str(exc).strip(),
                    table,
                )
                cls._run_vacuum(db, "bm25_retry_vacuum", f"VACUUM {table}")
                continue
            log.info("[MASSIVE] BM25 index created in %.4fs", perf_counter() - time_start)
            return

    @classmethod
    def _restore_bm25_index_resolving(cls, db: Db, built: Future[None]) -> None:
        """Build the BM25 index, then resolve `built`, also when the build failed."""
        try:
            cls._restore_bm25_index(db)
        finally:
            built.set_result(None)

    @classmethod
    def _restore_bm25_index_after_recompute(cls, db: Db, recomputed: Future[None]) -> None:
        """Build the BM25 index once the hive_posts recompute has committed; skip it when that task failed first.

        A no-op when an initial sync's index restore built it already. The build
        holds a snapshot for its whole length, often longer than the recompute.
        Started beside the recompute, that snapshot keeps every row version the
        recompute replaced (about 76 M at mainnet scale) visible to it, so
        hive_posts' index restore indexes them all and the vacuums after cannot
        remove them.
        """
        if recomputed.exception() is not None:
            log.info("[MASSIVE] Skipping BM25 index creation: the hive_posts task failed")
            return
        cls._restore_bm25_index(db)

    @classmethod
    def _drop_indexes_in_threads(cls) -> None:
        """Drop all registered indexes for the hivemind_app context in one call."""
        start_time = FOSM.start()
        cls._drop_all_registered_indexes()
        real_time = FOSM.stop(start_time)
        log.info("=== DROPPING INDEXES === (%.4fs)", real_time)
        FOSM.clear()

    @classmethod
    def _restore_indexes_in_threads(
        cls, deferred: Sequence[str] = (), order_votes: bool = False, build_search_index: bool = False
    ) -> None:
        """Restore all registered indexes in parallel across tables, except those of `deferred`.

        With `order_votes`, hive_votes is rewritten in post order first, on the
        thread that then restores its indexes. With `build_search_index`,
        hive_post_data's BM25 index is built on a thread of its own, and the
        vacuum after the hive_votes rewrite waits for it
        (_vacuum_ordered_hive_votes); without it, the fills phase builds the index.
        """
        cls._ensure_tables_exist(cls._TABLES_WITH_REGISTERED_INDEXES)
        start_time = FOSM.start()

        methods: list[tuple[str, Callable[..., Any], Sequence[Any]]] = []
        search_index_built: Future[None] = Future()
        if build_search_index:
            methods.append(('bm25_index', cls._restore_bm25_index_resolving, [cls.db(), search_index_built]))
        else:
            search_index_built.set_result(None)
        for table in cls._TABLES_WITH_REGISTERED_INDEXES:
            if table in deferred:
                log.info("[MASSIVE] Deferring index restore of %s.%s to finalization", SCHEMA_NAME, table)
                continue
            full_name = f'{SCHEMA_NAME}.{table}'
            if order_votes and table == 'hive_votes':
                methods.append((table, cls._order_and_restore_hive_votes, [cls.db(), full_name, search_index_built]))
            else:
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
    def ensure_off_synchronous_commit(cls) -> None:
        if cls._original_synchronous_commit_mode is not None:
            return

        """Disables non-critical indexes for faster sync, as well as foreign key constraints."""
        cls._original_synchronous_commit_mode = cls.db().query_one("SELECT current_setting('synchronous_commit');")
        cls.db().query_no_return("SET synchronous_commit = OFF;")

        log.info("[MASSIVE] SET synchronous_commit = OFF")

    @classmethod
    def ensure_on_synchronous_commit(cls) -> None:
        if cls._original_synchronous_commit_mode is None:
            return

        cls.db().query_no_return(f"SET synchronous_commit = {cls._original_synchronous_commit_mode}")
        cls._original_synchronous_commit_mode = None

        log.info("SET synchronous_commit = ON")

    @classmethod
    def disable_wal_safety_for_massive_sync(cls) -> None:
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
    def restore_wal_safety_after_massive_sync(cls) -> None:
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
    def is_initial_sync(cls) -> bool:
        """True until the first massive finalization commits last_completed_block_num.

        Gates the machinery that is only justified (and only safe) when the
        database holds no irreplaceable state yet: BM25 drop/rebuild and
        WAL-safety disabling. Cached per process — a crash
        during initial sync restarts with last_completed still at its seed
        value, so the gate re-engages correctly.
        """
        if cls._initial_sync is None:
            last_completed = cls.db().query_one(f"SELECT last_completed_block_num FROM {SCHEMA_NAME}.hive_state")
            cls._initial_sync = (last_completed or 0) <= SEED_LAST_COMPLETED_BLOCK
        return cls._initial_sync

    @classmethod
    def ensure_indexes_are_disabled(cls) -> None:
        if cls._indexes_were_disabled:
            return

        cls._drop_indexes_in_threads()

        if cls.is_initial_sync():
            # The tables stay LOGGED: at mainnet scale the UNLOGGED round trip cost
            # more than the WAL it saved, and a crash truncated UNLOGGED tables
            # (#460, docs/measurements/unlogged-massive-sync).
            #
            # The BM25 index is not HAF-registered, so _drop_indexes_in_threads
            # leaves it. Drop it like the registered indexes: otherwise every
            # massive insert into hive_post_data maintains it, and
            # _restore_bm25_index (IF NOT EXISTS) would never build it once over
            # the finished table. Safe on first run (IF EXISTS).
            cls.db().query_no_return("DROP INDEX IF EXISTS hivemind_app.hive_post_data_bm25_idx")

        cls.disable_autovacuum_for_massive_sync()

        cls._deferred_index_tables = []
        cls._indexes_were_disabled = True
        cls._indexes_were_enabled = False
        log.info("[MASSIVE] Indexes are disabled")

    @classmethod
    def ensure_fk_are_disabled(cls) -> None:
        if cls._fk_were_disabled:
            return

        cls._ensure_tables_exist(cls._TABLES_WITH_FKS + cls._TABLES_WITH_REGISTERED_INDEXES)

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
    def are_indexes_enabled(cls) -> bool:
        return cls._indexes_were_enabled

    @classmethod
    def ensure_indexes_are_enabled(cls, defer_to_finalization: bool = False, build_search_index: bool = False) -> None:
        """Restore the registered indexes, after SET LOGGED on any table still UNLOGGED.

        On an initial sync, hive_votes is first rewritten in post order
        (_order_hive_votes_by_post). With `defer_to_finalization` on an initial
        sync, the indexes of _INDEX_RESTORE_DEFERRED_TABLES are left for the
        finalization that follows (ensure_finalize_massive_sync) to restore after
        its recompute. Without it, indexes an earlier call deferred are restored too.
        With `build_search_index` on an initial sync, for a restore that no massive
        batch follows (each would update the index), the BM25 index is built beside
        the others instead of in finalization.
        """
        if cls.are_indexes_enabled():
            if not defer_to_finalization:
                cls._restore_deferred_indexes()
            return

        start_time = perf_counter()

        # A database left mid-sync by an older hivemind may still have UNLOGGED
        # tables; convert them before index creation, as BM25/pg_search does not
        # support UNLOGGED tables. Costs nothing when all are LOGGED.
        from hive.db.schema import ensure_tables_logged

        ensure_tables_logged(cls.db())

        log.info("Creating indexes: started")
        if defer_to_finalization and cls.is_initial_sync():
            cls._deferred_index_tables = list(cls._INDEX_RESTORE_DEFERRED_TABLES)
        cls._restore_indexes_in_threads(
            deferred=cls._deferred_index_tables,
            order_votes=cls.is_initial_sync(),
            build_search_index=build_search_index and cls.is_initial_sync(),
        )
        if not defer_to_finalization:
            cls._restore_deferred_indexes()
        log.info("Creating indexes: finished")

        cls._indexes_were_disabled = False
        cls._indexes_were_enabled = True
        log.info("Indexes are enabled")
        end_time = perf_counter()
        log.info("[MASSIVE] After massive sync actions done in %.4fs", end_time - start_time)

    @classmethod
    def _restore_deferred_indexes(cls) -> None:
        """Restore the indexes ensure_indexes_are_enabled deferred to finalization, if any."""
        for table in cls._deferred_index_tables:
            cls._restore_indexes_per_table(cls.db(), f'{SCHEMA_NAME}.{table}')
        cls._deferred_index_tables = []

    @classmethod
    def ensure_fk_are_enabled(cls) -> None:
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
    def _finish_hive_posts(
        cls,
        db: Db,
        massive_sync_preconditions: bool,
        last_imported_block: int,
        current_imported_block: int,
        recomputed: Future[None],
    ) -> None:
        """The hive_posts writes of finalization, on one connection, one after another.

        Two long UPDATEs of hive_posts in parallel would wait on each other's row
        locks for the length of the longer one, or deadlock; serialized, each sees
        the other's committed rows, and they write disjoint columns. The recompute
        runs on several connections, each on posts no other one writes
        (_recalculate_all_posts_votes_and_children), and ends before the next UPDATE.

        The indexes an initial sync deferred are restored after the recompute and
        before the root_id repair and the muted-parent propagation, which find
        their rows through them.

        `recomputed` is resolved once the recompute has committed (or skipped), or
        with the exception that ended the task before that.
        """
        try:
            with AutoDbDisposer(db, "finish_hive_posts") as db_mgr:
                # UPDATE: vote aggregates and `children`, in one pass.
                # Only the initial-massive full recompute runs here: it is idempotent,
                # so it is safe to repeat if finalization is interrupted before the
                # completion marker commits, and it writes only the rows whose values
                # change, so a repeat that finds hive_posts' indexes already restored
                # does not rewrite them for every row. Catch-ups keep the vote aggregates up to
                # date per batch (update_posts_rshares), and their ranged children update
                # applies *deltas*, so it must commit exactly once — it runs inside the
                # completion-marker transaction instead (_finalize_completion_marker).
                if massive_sync_preconditions:
                    cls._recalculate_all_posts_votes_and_children(db_mgr.db)
                recomputed.set_result(None)

                cls._restore_deferred_indexes()

                # UPDATE: `root_id`
                # Root posts are inserted with root_id = id and comments take their
                # parent's, so this only repairs root posts written with the former
                # root_id = 0 placeholder (a sync resumed across that change). It finds
                # them through hive_posts_root_id_id_idx, so it costs nothing otherwise.
                time_start = perf_counter()
                if massive_sync_preconditions:
                    sql = f"SELECT {SCHEMA_NAME}.update_hive_posts_root_id(NULL, NULL);"
                else:
                    sql = f"SELECT {SCHEMA_NAME}.update_hive_posts_root_id({last_imported_block}, {current_imported_block});"
                cls._execute_query_with_modified_work_mem(db=db_mgr.db, sql=sql)
                log.info("[MASSIVE] update_hive_posts_root_id executed in %.4fs", perf_counter() - time_start)
        except BaseException as exc:
            if not recomputed.done():
                recomputed.set_exception(exc)
            raise

        if massive_sync_preconditions:
            cls._finish_muted_parents(db)

    @classmethod
    def _recalculate_all_posts_votes_and_children(cls, db: Db) -> None:
        """recalculate_all_posts_votes_and_children's steps, its post id ranges on finalization_workers connections.

        Each range is a transaction of its own that writes only its own posts, so
        the ranges never wait on each other's row locks. Every step is idempotent:
        a rerun after an interruption anywhere computes the same values and
        rewrites only the rows still stale.
        """
        time_start = perf_counter()
        cls._execute_query_with_modified_work_mem(db=db, sql=f"SELECT {SCHEMA_NAME}.prepare_posts_children()")
        prepare_time = perf_counter() - time_start

        max_id = db.query_one(f"SELECT COALESCE(MAX(id), 0) FROM {SCHEMA_NAME}.hive_posts")
        ranges = cls._post_id_ranges(max_id, cls.finalization_workers * cls._RECOMPUTE_RANGES_PER_WORKER)
        methods = [
            (f'hive_posts ids {first}..{last}', cls._recalculate_posts_range, [db, first, last])
            for first, last in ranges
        ]
        ranges_start = perf_counter()
        cls.process_tasks_in_threads(
            "[MASSIVE] Recalculated the posts' votes and children by ranges.",
            methods,
            max_workers=cls.finalization_workers,
        )
        ranges_time = perf_counter() - ranges_start
        db.query_no_return(f"TRUNCATE TABLE {SCHEMA_NAME}.__post_children")
        log.info(
            "[MASSIVE] recalculate_all_posts_votes_and_children executed in %.4fs "
            "(prepare_posts_children %.4fs, %d ranges on %d connections %.4fs)",
            perf_counter() - time_start,
            prepare_time,
            len(ranges),
            cls.finalization_workers,
            ranges_time,
        )

    @classmethod
    def _post_id_ranges(cls, max_id: int, count: int) -> list[tuple[int, int]]:
        """`count` disjoint ranges of equal width covering the post ids 0 .. _MAX_POST_ID, the last one open-ended."""
        width = max_id // count + 1
        ranges = [(i * width, (i + 1) * width - 1) for i in range(count)]
        ranges[-1] = (ranges[-1][0], cls._MAX_POST_ID)
        return ranges

    @classmethod
    def _recalculate_posts_range(cls, db: Db, first_id: int, last_id: int) -> None:
        with AutoDbDisposer(db, f"recalculate_posts_{first_id}") as db_mgr:
            cls._execute_query(
                db_mgr.db, f"SELECT {SCHEMA_NAME}.recalculate_posts_votes_and_children({first_id}, {last_id})"
            )

    @classmethod
    def _finish_hive_feed_cache(cls, db, last_imported_block, current_imported_block) -> None:
        with AutoDbDisposer(db, "finish_hive_feed_cache") as db_mgr:
            time_start = perf_counter()
            sql = f"SELECT {SCHEMA_NAME}.update_feed_cache({last_imported_block}, {current_imported_block});"
            cls._execute_query_with_modified_work_mem(db=db_mgr.db, sql=sql)
            log.info("[MASSIVE] update_feed_cache executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_payout_stats_view(cls, db) -> None:
        with AutoDbDisposer(db, "finish_payout_stats_view") as db_mgr:
            time_start = perf_counter()
            PayoutStats.generate(db=db_mgr.db, separate_transaction=True)
            log.info("[MASSIVE] payout_stats_view executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_communities_posts_and_rank(cls, db) -> None:
        with AutoDbDisposer(db, "finish_communities_posts_and_rank") as db_mgr:
            time_start = perf_counter()
            db_mgr.db.query("START TRANSACTION")
            update_communities_posts_and_rank(db_mgr.db)
            db_mgr.db.query("COMMIT")
            log.info("[MASSIVE] update_communities_posts_and_rank executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_muted_parents(cls, db) -> None:
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
    def _finish_notification_cache(cls, db) -> None:
        with AutoDbDisposer(db, "finish_notification_cache") as db_mgr:
            time_start = perf_counter()
            sql = f"CALL {SCHEMA_NAME}.clear_muted_notifications();"
            cls._execute_query_with_modified_work_mem(db=db_mgr.db, sql=sql)
            log.info("[MASSIVE] clear_muted_notifications executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_vote_notifications(cls, db) -> None:
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
    def _finish_vote_notifications_ranged(cls, db, last_imported_block, current_imported_block) -> None:
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
    def _reptracker_block_processor_running(cls, db: Db) -> bool:
        """True when a session other than a hivemind one holds reputation_tracker's HAF block-processor lock.

        Every reptracker main() holds that lock for its lifetime; hivemind's sync holds it
        too (it reads reptracker_app), alongside its own, which tells its sessions apart.
        """
        return bool(
            db.query_one(
                "SELECT EXISTS (SELECT 1 FROM pg_locks l "
                "WHERE l.locktype = 'advisory' AND l.granted "
                "AND l.classid = hashtext('hive_fork_manager_app_lock') AND l.objid = hashtext('reputation_tracker') "
                "AND NOT EXISTS (SELECT 1 FROM pg_locks h WHERE h.pid = l.pid AND h.locktype = 'advisory' "
                "AND h.granted AND h.classid = hashtext('hive_fork_manager_app_lock') "
                "AND h.objid = hashtext(:app_name)))",
                app_name=APP_NAME,
            )
        )

    @classmethod
    def _wait_for_reputation_tracker(cls, db: Db, block_num: int) -> bool:
        """Wait until reputation_tracker has processed `block_num`, so the rescoring reads final reputations.

        Faster massive sync reaches finalization before reptracker reaches its block, and a
        rescoring then reads reputations that are still behind (#531). Returns True once
        reptracker reached the block, or as soon as no reptracker block processor runs
        (nothing would advance it, e.g. a test setup that syncs it after hivemind): the
        rescoring then reads the reputations as they are, with a warning. Returns False
        when a shutdown request stops the wait.
        """
        polls = 0
        while True:
            reptracker_block = db.query_one(f"SELECT hive.app_get_current_block_num('{REPTRACKER_SCHEMA_NAME}')") or 0
            if reptracker_block >= block_num:
                if polls:
                    log.info("[MASSIVE] %s reached block %d", REPTRACKER_SCHEMA_NAME, reptracker_block)
                return True
            if not cls._reptracker_block_processor_running(db):
                log.warning(
                    "[MASSIVE] %s is at block %d, behind hivemind's %d, and no reputation_tracker block processor "
                    "runs; rescoring reputation notifications from the reputations as they are",
                    REPTRACKER_SCHEMA_NAME,
                    reptracker_block,
                    block_num,
                )
                return True
            if cls._interrupted("reputation notification scores"):
                return False
            if polls % cls._REPTRACKER_LOG_EVERY_POLLS == 0:
                log.info(
                    "[MASSIVE] Waiting for %s (block %d) to reach block %d before rescoring reputation notifications",
                    REPTRACKER_SCHEMA_NAME,
                    reptracker_block,
                    block_num,
                )
            polls += 1
            sleep(cls._REPTRACKER_POLL_SECONDS)

    @classmethod
    def _finish_reputation_notification_scores(cls, db) -> None:
        """Recalculate reputation-based notification scores using final reputation data.

        During massive sync, the scores of the notifications scored by their
        source's reputation (subscribe, reply, reblog, follow, mention) are computed
        from reptracker_app.account_reputations at flush time. Since the reputation
        tracker runs concurrently, scores may reflect incomplete reputation data.
        This finalization step corrects them using the final values. The initial
        sync's flushes keep these rows whatever their score
        (reputation_notification_cut_deferred), so the score > 0 cut that live
        sync applies at write time is applied here, on the final scores.
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
                JOIN final_rep fr ON ha.id = fr.account_id
                WHERE hnc.src = ha.id
                    AND hnc.type_id IN (11, 12, 13, 14, 15, 16)
                    AND hnc.score != COALESCE(fr.rep, 25)
            """
            delete_sql = f"""
                DELETE FROM {SCHEMA_NAME}.hive_notification_cache
                WHERE type_id IN (11, 12, 13, 14, 15, 16)
                    AND score <= 0
            """
            db_mgr.db.query("START TRANSACTION")
            cls._execute_query_with_modified_work_mem(db=db_mgr.db, sql=sql, separate_transaction=False)
            cls._execute_query(db_mgr.db, delete_sql)
            db_mgr.db.query("COMMIT")
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
    def process_tasks_in_threads(
        cls,
        info: str,
        methods: Sequence[tuple[str, Callable[..., Any], Sequence[Any]]],
        max_workers: int | None = None,
    ) -> None:
        """Run each (description, method, args) task in a pool of `max_workers` threads (default Db.max_connections).

        Returns once every task finished. When a task fails, the tasks not started yet are
        cancelled and the running ones are waited for before the first failure is re-raised,
        so no task (and no statement it issued) outlives the call.
        """
        start_time = perf_counter()
        completedThreads = 0
        with ThreadPoolExecutor(max_workers=max_workers or Db.max_connections) as pool:
            futures = {
                pool.submit(cls.time_collector, method, args): (description) for (description, method, args) in methods
            }
            for future in as_completed(futures):
                description = futures[future]
                completedThreads = completedThreads + 1
                try:
                    elapsedTime = future.result()
                    FOSM.final_stat(description, elapsedTime)
                except Exception as exc:
                    log.error(f'{description!r} generated an exception: {exc}')
                    pool.shutdown(wait=True, cancel_futures=True)
                    raise exc

        log.info(f'{info} Real elapsed time: {perf_counter() - start_time:.3f}, completed threads: {completedThreads}')

    @classmethod
    def _interrupted(cls, phase) -> bool:
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
    def _finish_all_tables(cls, massive_sync_preconditions, last_imported_block, current_imported_block) -> bool:
        """Fill derived tables after massive sync. Returns True when finalization completed.

        Ordering contract: all fill tasks run (idempotently re-runnable) BEFORE
        _finalize_completion_marker commits last_completed_block_num as the very
        last write. Never add a task after the marker, and never let a task
        commit the marker early — see #337 for the incident this prevents.
        """
        start_time = FOSM.start()

        log.info("#############################################################################")

        if cls._interrupted("Part 0 fills"):
            return False

        # Dependency graph (A <- B: B reads what A writes), which the parts follow:
        #   hive_posts: vote aggregates + children (by post id ranges on several
        #       connections), root_id repair, muted parents (one thread, see
        #       _finish_hive_posts) <- vote_notifications of the initial path, which
        #       scores by vote_rshares/abs_rshares
        #   feed cache, payout_stats_view, communities rank, BM25 index: read no
        #       column a finalization task writes, so they run beside hive_posts;
        #       an initial sync's index restore built the BM25 index already, else
        #       its build starts after the hive_posts recompute commits
        #       (_restore_bm25_index_after_recompute)
        #   notification_cache, vote_notifications <- reputation scores
        #   every task <- completion marker
        # Part 0 is everything without a predecessor; its critical path is the
        # hive_posts thread.
        recomputed: Future[None] = Future()
        methods: list[tuple[str, Callable[..., Any], Sequence[Any]]] = [
            ('hive_feed_cache', cls._finish_hive_feed_cache, [cls.db(), last_imported_block, current_imported_block]),
            (
                'hive_posts',
                cls._finish_hive_posts,
                [cls.db(), massive_sync_preconditions, last_imported_block, current_imported_block, recomputed],
            ),
        ]
        if massive_sync_preconditions:
            methods += [
                ('payout_stats_view', cls._finish_payout_stats_view, [cls.db()]),
                ('communities_posts_and_rank', cls._finish_communities_posts_and_rank, [cls.db()]),
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
        # The BM25 index when the index restore did not build it (a restore that massive
        # batches followed, or a catch-up). It runs in parallel with the fills above,
        # off their critical path, from the moment the hive_posts recompute commits
        # (_restore_bm25_index_after_recompute).
        methods.append(('bm25_index', cls._restore_bm25_index_after_recompute, [cls.db(), recomputed]))
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
        # flushed (and, on the initial-massive path, muted ones cleared). Runs sequentially
        # to avoid concurrent access to hive_notification_cache with the tasks above. Every
        # initial sync needs it, however short: its flushes deferred the score > 0 cut here.
        # reptracker syncs beside hivemind, so the rescoring waits for it to reach hivemind's
        # block first; the reputations it reads are then those live sync scores with.
        if massive_sync_preconditions or last_imported_block <= SEED_LAST_COMPLETED_BLOCK:
            if not cls._wait_for_reputation_tracker(cls.db(), current_imported_block):
                return False
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
    def disable_autovacuum_for_massive_sync(cls) -> None:
        """Hand vacuum scheduling of the race-prone table(s) over to boundary vacuums."""
        for table in cls.MASSIVE_VACUUM_THRESHOLDS:
            cls.db().query_no_return(
                f"ALTER TABLE {SCHEMA_NAME}.{table} SET (autovacuum_enabled = off, toast.autovacuum_enabled = off)"
            )
        log.info("[MASSIVE] Autovacuum disabled on %s; boundary vacuums take over", list(cls.MASSIVE_VACUUM_THRESHOLDS))

    @classmethod
    def restore_autovacuum_after_massive_sync(cls) -> None:
        for table in cls.MASSIVE_VACUUM_THRESHOLDS:
            cls.db().query_no_return(
                f"ALTER TABLE {SCHEMA_NAME}.{table} RESET (autovacuum_enabled, toast.autovacuum_enabled)"
            )
        log.info("[MASSIVE] Autovacuum reloptions restored on %s", list(cls.MASSIVE_VACUUM_THRESHOLDS))

    @classmethod
    def run_boundary_vacuums(cls, db: Db | None = None) -> list[str]:
        """Vacuum any watched table whose dead tuples exceed its threshold.

        Called between chunks with no flush statement in flight; plain VACUUM
        (visibility map limits it to recently-churned pages, and the heavy
        indexes are dropped during massive sync anyway). The thresholds are read,
        and the vacuum connections cloned, on `db` (default: the shared connection).
        """
        db = db or cls.db()
        names = ','.join(f"'{t}'" for t in cls.MASSIVE_VACUUM_THRESHOLDS)
        rows = db.query_all(
            f"SELECT relname, n_dead_tup FROM pg_stat_user_tables WHERE schemaname = '{SCHEMA_NAME}' AND relname IN ({names})"
        )
        due = [
            row._mapping['relname']
            for row in rows
            if row._mapping['n_dead_tup'] >= cls.MASSIVE_VACUUM_THRESHOLDS[row._mapping['relname']]
        ]
        if not due:
            return []

        def vacuum_table(table, db) -> None:
            cls._run_vacuum(db, "boundary_vacuum", f"VACUUM {SCHEMA_NAME}.{table}")

        methods = [('VACUUM ' + table, vacuum_table, [table, db]) for table in due]
        cls.process_tasks_in_threads("Boundary vacuum on hivemind tables", methods, max_workers=cls.vacuum_workers)
        return due

    @classmethod
    def vacuum_tables_in_threads(cls, plain=(), frozen=(), compacted=()) -> None:
        """Vacuum each table once, in parallel, with ANALYZE: plain for `plain`, FREEZE for `frozen`, FULL for `compacted`.

        FULL rewrites the table under ACCESS EXCLUSIVE (over an hour for the largest
        tables at full scale) and discards its freeze and visibility map, so a
        compacted table needs a frozen vacuum after its last write.
        """

        def vacuum_table(table, options, db) -> None:
            log.info(f"Vacuuming table {table} ({options})")
            cls._run_vacuum(db, "vacuum", f"VACUUM ({options}) {table}")

        methods = [('VACUUM ' + table, vacuum_table, [table, "VERBOSE, ANALYZE", cls.db()]) for table in plain]
        methods += [
            ('VACUUM ' + table, vacuum_table, [table, "FREEZE, VERBOSE, ANALYZE", cls.db()]) for table in frozen
        ]
        methods += [
            ('VACUUM ' + table, vacuum_table, [table, "FULL, VERBOSE, ANALYZE", cls.db()]) for table in compacted
        ]

        cls.process_tasks_in_threads("Requesting vacuum on hivemind tables", methods, max_workers=cls.vacuum_workers)

    @classmethod
    def _run_vacuum(cls, db: Db, name: str, sql: str) -> None:
        """Run a VACUUM statement on a connection of its own; skip it when no connection can be opened.

        The database is shared with other HAF apps, so its connection slots may be
        exhausted (too many clients, slots reserved for superusers). A vacuum only
        speeds up what follows it, so after a few attempts it is skipped (autovacuum
        covers the table later) rather than failing finalization.
        """
        for attempt in range(1, cls._VACUUM_CONNECT_ATTEMPTS + 1):
            try:
                disposer = AutoDbDisposer(db, name)
                break
            except psycopg2.OperationalError as exc:
                if attempt == cls._VACUUM_CONNECT_ATTEMPTS:
                    log.warning("Skipping %s: no connection after %d attempts: %s", sql, attempt, exc)
                    return
                log.warning(
                    "Cannot connect for %s (attempt %d/%d): %s; retrying after backoff",
                    sql,
                    attempt,
                    cls._VACUUM_CONNECT_ATTEMPTS,
                    exc,
                )
                sleep(cls._VACUUM_CONNECT_BACKOFF_SECONDS * attempt)
        with disposer as db_mgr:
            db_mgr.db.query_no_return_autocommit(sql)

    @classmethod
    def start_visibility_watch(cls) -> None:
        """Start, once per process, the background VisibilityWatch that vacuums the large tables until all-visible."""
        if cls._visibility_watch is not None:
            return
        cls._visibility_watch = VisibilityWatch(cls.db(), cls._vacuum_for_visibility)
        cls._visibility_watch.start()

    @classmethod
    def stop_visibility_watch(cls, timeout: float = 30.0) -> None:
        """Stop the visibility watch, cancelling its running vacuums, and wait up to `timeout` seconds for it."""
        watch = cls._visibility_watch
        if watch is None or not watch.is_alive():
            return
        watch.stop()
        try:
            cls.db().query_no_return(
                "SELECT pg_cancel_backend(pid) FROM pg_stat_activity "
                f"WHERE application_name = 'hivemind_{cls._VISIBILITY_VACUUM_NAME}' AND usename = current_user"
            )
        except psycopg2.Error as exc:
            # Its vacuums then end with their connections, at the latest when the
            # next start terminates the leftover hivemind_* connections.
            log.warning("Cannot cancel the visibility vacuums: %s", exc)
        watch.join(timeout)
        if watch.is_alive():
            log.warning("The visibility watch did not stop within %.0fs", timeout)

    @classmethod
    def _vacuum_for_visibility(cls, tables: Sequence[str]) -> None:
        def vacuum_table(table: str, db: Db) -> None:
            cls._run_vacuum(db, cls._VISIBILITY_VACUUM_NAME, f"VACUUM {table}")

        methods = [('VACUUM ' + table, vacuum_table, [table, cls.db()]) for table in tables]
        cls.process_tasks_in_threads("Visibility vacuum on hivemind tables", methods, max_workers=cls.vacuum_workers)

    @classmethod
    def vacuum_all_hivemind_tables_in_threads(cls) -> None:
        """Vacuum every hivemind table once before finalization.

        Tables finalization doesn't write are frozen here, their last vacuum of
        the sync (HAF queues no freeze for hive_post_data or hive_permlink_data,
        which have no registered indexes). The tables it writes get a plain
        vacuum so its updates reuse the freed space; they are frozen after it.
        """
        log.info("Requesting vacuum on hivemind tables")
        sql = f"""
SELECT table_schema || '.' || table_name AS table_name
FROM information_schema.tables
WHERE table_schema = '{SCHEMA_NAME}' AND table_type = 'BASE TABLE'
"""
        rows = cls.db().query_all(sql)
        tables = [row._mapping["table_name"] for row in rows]
        written = cls._finalization_written_tables()

        cls.vacuum_tables_in_threads(
            plain=[t for t in tables if t in written], frozen=[t for t in tables if t not in written]
        )

    @classmethod
    def _finalization_written_tables(cls):
        return [f"{SCHEMA_NAME}.{table}" for table in cls._FINALIZATION_WRITTEN_TABLES]

    @classmethod
    def ensure_finalize_massive_sync(cls, last_imported_blocks, last_completed_blocks) -> bool:
        if last_imported_blocks > last_completed_blocks:
            if cls.db().is_trx_active():
                cls.db().query_no_return("COMMIT")

            # The payouts the last pipelined Stage B left, before the recompute reads is_paidout.
            cls.db().query_no_return(f"SELECT {SCHEMA_NAME}.apply_deferred_payouts()")

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
                cls._restore_deferred_indexes()
                return True

            if is_initial_massive:
                # The vote/children recompute rewrites most of hive_posts, so compact it
                # once, after its last write, then freeze it since the rewrite discards
                # the freeze.
                hive_posts = f"{SCHEMA_NAME}.hive_posts"
                cls.vacuum_tables_in_threads(
                    frozen=[t for t in cls._finalization_written_tables() if t != hive_posts], compacted=[hive_posts]
                )
                cls.vacuum_tables_in_threads(frozen=[hive_posts])

            log_coverage(cls.db(), "[MASSIVE] After finalization")
            log.info("[MASSIVE] Massive sync complete!")
            return True
        cls._restore_deferred_indexes()
        return False

    @staticmethod
    def status():
        """Basic health status: head block/time, current age (secs)."""
        sql = f"SELECT * FROM {SCHEMA_NAME}.get_head_state()"
        row = DbState.db().query_row(sql)._mapping
        return {
            'db_head_block': row['num'],
            'db_head_time': str(row['created_at']),
            'db_head_age': int(time.time() - row['age']),
        }

    @classmethod
    def _is_schema_loaded(cls) -> bool:
        """Check if the schema has been loaded into db yet."""
        return bool(cls.db().query_one(f"SELECT 1 FROM pg_catalog.pg_tables WHERE schemaname = '{SCHEMA_NAME}';"))

    @classmethod
    def _is_feed_cache_empty(cls) -> bool:
        """Check if the hive_feed_cache table is empty.

        If empty, it indicates that the massive sync has not finished.
        """
        return not cls.db().query_one(f"SELECT 1 FROM {SCHEMA_NAME}.hive_feed_cache LIMIT 1")
