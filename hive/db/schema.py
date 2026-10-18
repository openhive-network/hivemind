"""Db schema definitions and setup routines."""

import logging
import os
from pathlib import Path

from hive.conf import SCHEMA_NAME, SCHEMA_OWNER_NAME
from hive.indexer.hive_db.haf_functions import prepare_app_context
from hive.version import GIT_DATE, GIT_REVISION, VERSION

log = logging.getLogger(__name__)

# Set during setup() — indicates whether pg_search (ParadeDB) extension is available
pg_search_available = False


def teardown(db) -> None:
    """Drop all tables by dropping the schema."""
    db.query_no_return(f"DROP SCHEMA IF EXISTS {SCHEMA_NAME} CASCADE")


def create_statistics(db) -> None:
    """Create extended statistics dependencies for various tables."""
    sql = f"CREATE STATISTICS IF NOT EXISTS {SCHEMA_NAME}.hive_accounts_stats (dependencies) ON id, haf_id, name, created_at FROM {SCHEMA_NAME}.hive_accounts;"
    db.query_no_return(sql)
    sql = f"CREATE STATISTICS IF NOT EXISTS {SCHEMA_NAME}.hive_tag_data_stats (dependencies) ON id, tag FROM {SCHEMA_NAME}.hive_tag_data;"
    db.query_no_return(sql)
    sql = f"CREATE STATISTICS IF NOT EXISTS {SCHEMA_NAME}.hive_posts_stats (dependencies) ON created_at, block_num_created FROM {SCHEMA_NAME}.hive_posts;"
    db.query_no_return(sql)
    sql = f"CREATE STATISTICS IF NOT EXISTS {SCHEMA_NAME}.hive_reblogs_stats (dependencies) ON created_at, block_num FROM {SCHEMA_NAME}.hive_reblogs;"
    db.query_no_return(sql)
    sql = f"CREATE STATISTICS IF NOT EXISTS {SCHEMA_NAME}.hive_communities_stats (dependencies) ON id, name FROM {SCHEMA_NAME}.hive_communities;"
    db.query_no_return(sql)
    sql = f"CREATE STATISTICS IF NOT EXISTS {SCHEMA_NAME}.hive_subscriptions_stats (dependencies) ON created_at, block_num FROM {SCHEMA_NAME}.hive_subscriptions;"
    db.query_no_return(sql)


def _try_create_extension(db, ext_name) -> bool:
    """Try to create an extension, return True if successful."""
    try:
        # CASCADE: pg_search >= 0.25 depends on the vector extension
        db.query(f'CREATE EXTENSION IF NOT EXISTS {ext_name} CASCADE;')
        return True
    except Exception:
        # With autocommit=True the failed statement is already rolled back
        return False


def insert_seed_data(db) -> None:
    """Insert the minimal seed rows required for hivemind to operate.

    These rows must exist before any block processing starts:
    - hive_state: tracks sync progress (last_completed_block_num = 1)
    - permlink/category/tag ID 0: sentinel empty-string rows
    - accounts 0-4: system accounts (empty, miners, null, temp, initminer)
    - post ID 0: sentinel root post
    """
    sqls = [
        f"INSERT INTO {SCHEMA_NAME}.hive_state (last_completed_block_num, db_version, hivemind_git_rev, hivemind_git_date, hivemind_version)"
        f" VALUES (1, 0, '{GIT_REVISION}', '{GIT_DATE}', '{VERSION}')"
        f" ON CONFLICT DO NOTHING",
        f"INSERT INTO {SCHEMA_NAME}.hive_permlink_data (id, permlink) VALUES (0, '') ON CONFLICT DO NOTHING",
        f"INSERT INTO {SCHEMA_NAME}.hive_category_data (id, category) VALUES (0, '') ON CONFLICT DO NOTHING",
        f"INSERT INTO {SCHEMA_NAME}.hive_tag_data (id, tag) VALUES (0, '') ON CONFLICT DO NOTHING",
        f"INSERT INTO {SCHEMA_NAME}.hive_accounts (id, name, created_at) VALUES (0, '', '1970-01-01T00:00:00') ON CONFLICT DO NOTHING",
        f"INSERT INTO {SCHEMA_NAME}.hive_accounts (name, created_at) VALUES ('miners',    '2016-03-24 16:05:00') ON CONFLICT DO NOTHING",
        f"INSERT INTO {SCHEMA_NAME}.hive_accounts (name, created_at) VALUES ('null',      '2016-03-24 16:05:00') ON CONFLICT DO NOTHING",
        f"INSERT INTO {SCHEMA_NAME}.hive_accounts (name, created_at) VALUES ('temp',      '2016-03-24 16:05:00') ON CONFLICT DO NOTHING",
        f"INSERT INTO {SCHEMA_NAME}.hive_accounts (name, created_at) VALUES ('initminer', '2016-03-24 16:05:00') ON CONFLICT DO NOTHING",
        f"""
        INSERT INTO
            {SCHEMA_NAME}.hive_posts(id, root_id, parent_id, author_id, permlink_id, category_id,
                community_id, created_at, depth, block_num, block_num_created
            )
        VALUES
            (0, 0, 0, 0, 0, 0, 0, now(), 0, 0, 0)
        ON CONFLICT DO NOTHING;
        """,
    ]
    for sql in sqls:
        db.query(sql)


def setup(db, admin_db) -> None:
    """Creates all tables and seed data"""

    # create schema and aux functions
    admin_db.query(f'CREATE SCHEMA IF NOT EXISTS {SCHEMA_NAME} AUTHORIZATION {SCHEMA_OWNER_NAME};')
    admin_db.query(f'CREATE SCHEMA IF NOT EXISTS hivemind_endpoints AUTHORIZATION {SCHEMA_OWNER_NAME};')
    admin_db.query(f'CREATE SCHEMA IF NOT EXISTS hivemind_postgrest_utilities AUTHORIZATION {SCHEMA_OWNER_NAME};')

    # Create extensions before table creation (needed for BM25 index type)
    # Create ParadeDB pg_search extension for BM25 search (optional)
    global pg_search_available
    pg_search_available = _try_create_extension(admin_db, 'pg_search')
    if not pg_search_available:
        log.warning("pg_search extension not available — BM25 full-text search will be disabled")

    # Create plpython3u extension (requires superuser privileges)
    # Note: plpython3u is an untrusted language, only superusers can use it
    admin_db.query('CREATE EXTENSION IF NOT EXISTS plpython3u;')

    prepare_app_context(db=db)

    if pg_search_available:
        # Create a dummy is_top_level_post function BEFORE table creation so the
        # BM25 index WHERE clause can refer to it
        sql = f"""
        CREATE OR REPLACE FUNCTION {SCHEMA_NAME}.is_top_level_post(post_id INTEGER)
        RETURNS BOOLEAN
        LANGUAGE sql
        IMMUTABLE PARALLEL SAFE
        AS $$
          SELECT TRUE;
        $$;
        """
        db.query_no_return(sql)

    # Create tables and indexes from SQL script
    sql_scripts_dir_path = Path(__file__).parent / 'sql_scripts'
    execute_sql_script(db.query_no_return, sql_scripts_dir_path / 'schema' / 'create_tables.sql')

    if pg_search_available:
        # Create BM25 index (requires pg_search extension)
        sql = f"""
        CREATE INDEX IF NOT EXISTS hive_post_data_bm25_idx ON {SCHEMA_NAME}.hive_post_data
            USING bm25 (id, title, body)
            WITH (key_field = 'id', text_fields = '{{"title": {{"record": "position"}}, "body": {{"record": "position"}}}}')
            WHERE {SCHEMA_NAME}.is_top_level_post(id);
        """
        db.query_no_return(sql)

        # Now that tables exist, replace the function with its real implementation that
        # references the hive_posts table
        sql = f"""
        CREATE OR REPLACE FUNCTION {SCHEMA_NAME}.is_top_level_post(post_id INTEGER)
        RETURNS BOOLEAN
        LANGUAGE sql
        IMMUTABLE PARALLEL SAFE
        AS $$
          SELECT EXISTS (
            SELECT 1 FROM {SCHEMA_NAME}.hive_posts hp
            WHERE hp.id = post_id AND hp.depth = 0
          );
        $$;
        """
        db.query_no_return(sql)

    # Register indexes with HAF for managed lifecycle (drop/restore during massive sync)
    # Uses hive.app_register_index_dependency() which is SECURITY DEFINER — app role is sufficient
    execute_sql_script(db.query_no_return, sql_scripts_dir_path / 'schema' / 'register_indexes.sql')

    # Create foreign key constraints
    execute_sql_script(db.query_no_return, sql_scripts_dir_path / 'schema' / 'create_foreign_keys.sql')

    create_statistics(db)

    reset_autovac(db)  # tune auto vacuum/analyze
    set_fillfactor(db)

    # default rows
    insert_seed_data(db)
    db.query(f"UPDATE {SCHEMA_NAME}.hive_state SET db_version = 0")

    sql = f"CREATE INDEX hive_communities_ft1 ON {SCHEMA_NAME}.hive_communities USING GIN (to_tsvector('english', title || ' ' || about))"
    db.query(sql)

    sql = f"""
          CREATE TABLE IF NOT EXISTS {SCHEMA_NAME}.hive_db_patch_level
          (
            level SERIAL NOT NULL PRIMARY KEY,
            patch_date timestamp without time zone NOT NULL,
            patched_to_revision TEXT
          );
    """
    db.query_no_return(sql)

    # sqlalchemy doesn't allow to use DESC in CreateUnique
    sql = f"""
        CREATE UNIQUE INDEX IF NOT EXISTS hive_post_tags_tag_id_post_id_idx
        ON {SCHEMA_NAME}.hive_post_tags USING btree (tag_id, post_id DESC)
        """
    db.query_no_return(sql)

    _setup_admin_runtime_code(admin_db)


def _setup_admin_runtime_code(admin_db) -> None:
    """(Re)create the plpython3u runtime functions, which need admin privileges."""
    sql_scripts_dir_path = Path(__file__).parent / 'sql_scripts'
    admin_sql_scripts = [
        "postgrest/utilities/preprocess_search_query.sql",
    ]
    for script in admin_sql_scripts:
        execute_sql_script(admin_db.query_no_return, sql_scripts_dir_path / script)


def _postgrest_scripts() -> list[str]:
    """Return the scripts included by postgrest/load_order.sql, in order, as paths relative to sql_scripts/."""
    lines = (Path(__file__).parent / 'sql_scripts' / 'postgrest' / 'load_order.sql').read_text().splitlines()
    includes = (line.strip().removeprefix('\\ir ') for line in lines if line.strip().startswith('\\ir '))
    return [os.path.normpath(f'postgrest/{include.strip()}') for include in includes]


def setup_runtime_code(db) -> None:
    sql_scripts = [
        "utility_functions.sql",
        "follow_ops.sql",
        "hive_accounts_view.sql",
        "hive_accounts_info_view.sql",
        "hive_posts_base_view.sql",
        "hive_posts_view.sql",
        "hive_votes_view.sql",
        "hive_muted_accounts_by_id_view.sql",
        "get_post_view_by_id.sql",
        "hive_post_operations.sql",
        "head_block_time.sql",
        "update_feed_cache.sql",
        "payout_stats_view.sql",
        "update_communities_rank.sql",
        "delete_hive_posts_mentions.sql",
        "notifications_view.sql",
        "prune_notification_cache.sql",
        "clear_muted_notifications.sql",
        "hot_and_trends.sql",
        "update_hive_posts_children_count.sql",
        "update_posts_rshares.sql",
        "update_hive_post_root_id.sql",
        "delete_reblog_feed_cache.sql",
        "is_superuser.sql",
        "update_hive_blocks_consistency_flag.sql",
        "update_table_statistics.sql",
        "upgrade/update_db_patchlevel.sql",
        "hafapp_api.sql",
        "massive_sync.sql",
        "grant_hivemind_user.sql",
        "community.sql",
        "community_utils.sql",
        *_postgrest_scripts(),
    ]

    sql_scripts_dir_path = Path(__file__).parent / 'sql_scripts'
    for script in sql_scripts:
        execute_sql_script(db.query_no_return, sql_scripts_dir_path / script)

    # Move this part here, to mark latest db patch level as current Hivemind revision (which just created schema).
    sql = f"""
          INSERT INTO {SCHEMA_NAME}.hive_db_patch_level
          (patch_date, patched_to_revision)
          select ds.patch_date, ds.patch_revision
          from
          (
          values
          (now(), '{{}}')
          ) ds (patch_date, patch_revision)
          WHERE NOT EXISTS (SELECT NULL FROM hivemind_app.hive_db_patch_level hpl WHERE hpl.patched_to_revision = ds.patch_revision);
          ;
          """

    # Update hivemind_app.hive_stats table
    sql_hive_state_update = f"""
                            UPDATE {SCHEMA_NAME}.hive_state
                            SET
                                hivemind_git_date = CASE
                                    WHEN hivemind_git_date != '{GIT_DATE}' THEN '{GIT_DATE}'
                                    ELSE hivemind_git_date
                                END,
                                hivemind_git_rev = CASE
                                    WHEN hivemind_git_rev != '{GIT_REVISION}' THEN '{GIT_REVISION}'
                                    ELSE hivemind_git_rev
                                END,
                                hivemind_version = CASE
                                    WHEN hivemind_version != '{VERSION}' THEN '{VERSION}'
                                    ELSE hivemind_version
                                END
                            WHERE hivemind_git_date != '{GIT_DATE}'
                                OR hivemind_git_rev != '{GIT_REVISION}'
                                OR hivemind_version != '{VERSION}';
                            """

    db.query_no_return(sql.format(GIT_REVISION))
    db.query_no_return(sql_hive_state_update)

    # register in the HAF application registry; needs hivemind_app._batch_queue
    # (massive_sync.sql above) for the completed-block function (haf#341)
    from hive.indexer.hive_db.haf_functions import register_application

    register_application(db)


def perform_db_upgrade(db, admin_db) -> None:
    sql_scripts_dir_path = Path(__file__).parent / 'sql_scripts'

    sql_scripts = [
        "postgres_handle_view_changes.sql",
        "upgrade/upgrade_table_schema.sql",
        "upgrade/upgrade_runtime_migration.sql",
    ]

    sql_scripts_dir_path = Path(__file__).parent / 'sql_scripts'
    for script in sql_scripts:
        execute_sql_script(admin_db.query_no_return, sql_scripts_dir_path / script)

    # setup_runtime_code() runs as the schema owner and cannot reload these
    _setup_admin_runtime_code(admin_db)

    log.info("Database schema upgrade completed.")

    needs_vacuum = admin_db.query_one(
        'SELECT COALESCE((SELECT hd.vacuum_needed FROM hivemind_app.hive_db_vacuum_needed hd WHERE hd.vacuum_needed LIMIT 1), False) AS needs_vacuum'
    )

    if needs_vacuum:
        log.info("Attempting to run VACUUM FULL on upgraded database")
        admin_db.query_no_return("VACUUM FULL VERBOSE ANALYZE;")
    else:
        log.info("Skipping VACUUM FULL on upgraded database (no vacuum request)")


def reset_autovac(db) -> None:
    """Initializes/resets per-table autovacuum/autoanalyze params.

    We use a scale factor of 0 and specify exact threshold tuple counts,
    per-table, in the format (autovacuum_threshold, autoanalyze_threshold)."""

    autovac_config = {  # vacuum  analyze
        'hive_accounts': (50000, 100000),
        'hive_posts': (2500, 10000),
        'hive_post_tags': (5000, 10000),
    }

    for table, (n_vacuum, n_analyze) in autovac_config.items():
        sql = f"""
ALTER TABLE {SCHEMA_NAME}.{table} SET (autovacuum_vacuum_scale_factor = 0,
                                  autovacuum_vacuum_threshold = {n_vacuum},
                                  autovacuum_analyze_scale_factor = 0,
                                  autovacuum_analyze_threshold = {n_analyze});
"""
        db.query(sql)


def set_fillfactor(db) -> None:
    """Initializes/resets FILLFACTOR for tables which are intensively updated"""

    # Lowered fillfactor for hive_votes table in attempt to speed up update_posts_rshares procedure
    fillfactor_config = {'hive_posts': 90, 'hive_post_data': 100, 'hive_votes': 90}

    for table, fillfactor in fillfactor_config.items():
        sql = f"ALTER TABLE {SCHEMA_NAME}.{table} SET (FILLFACTOR = {fillfactor});"
        db.query(sql)


def set_logged_table_attribute(db, logged):
    """Initializes/resets LOGGED/UNLOGGED attribute for tables which are intensively updated.

    Tables are converted in parallel to minimize total conversion time.
    The largest table (hive_votes at ~319GB) is the bottleneck.

    Tables with foreign key relationships must be converted together. PostgreSQL
    requires that if a referenced table is UNLOGGED, all tables with FKs pointing
    to it must also be UNLOGGED (and vice versa). We convert in two phases:
      Phase 1: small dependent tables (hive_reblogs, hive_mentions) that have FKs
               to hive_accounts and hive_posts
      Phase 2: the main large tables (including hive_accounts, hive_posts)
    """
    from concurrent.futures import ThreadPoolExecutor, as_completed
    from time import perf_counter

    # Phase 1: small tables with FKs referencing tables in phase 2.
    # Must be converted first when going to UNLOGGED, last when going to LOGGED.
    fk_dependent_tables = [
        'hive_reblogs',  # FKs to hive_accounts, hive_posts
        'hive_mentions',  # FKs to hive_posts, hive_accounts
    ]

    # Phase 2: large tables, ordered by size descending for better parallelism
    main_tables = [
        'hive_votes',  # ~319 GB
        'hive_post_data',  # ~127 GB
        'hive_posts',  # ~83 GB
        'hive_permlink_data',  # ~27 GB
        'hive_post_tags',  # ~12 GB
        'hive_accounts',  # ~748 MB
    ]

    mode = 'LOGGED' if logged else 'UNLOGGED'

    # When setting UNLOGGED: dependents first, then referenced tables
    # When setting LOGGED: referenced tables first, then dependents
    if logged:
        phases = [('main', main_tables), ('dependent', fk_dependent_tables)]
    else:
        phases = [('dependent', fk_dependent_tables), ('main', main_tables)]

    all_tables = fk_dependent_tables + main_tables
    log.info(f"Converting {len(all_tables)} tables to {mode} in two phases...")
    start_time = perf_counter()

    def convert_table(table):
        """Convert a single table - runs in separate thread with own connection."""
        table_start = perf_counter()
        thread_db = db.clone(f'logged_convert_{table}')
        try:
            sql = f"ALTER TABLE {SCHEMA_NAME}.{table} SET {mode}"
            thread_db.query_no_return(sql)
            elapsed = perf_counter() - table_start
            return (table, elapsed, None)
        except Exception as e:
            elapsed = perf_counter() - table_start
            return (table, elapsed, e)
        finally:
            thread_db.close()

    for _phase_name, tables in phases:
        with ThreadPoolExecutor(max_workers=len(tables)) as executor:
            futures = {executor.submit(convert_table, table): table for table in tables}

            for future in as_completed(futures):
                table, elapsed, error = future.result()
                if error:
                    log.error(f"Failed to set {mode} on {SCHEMA_NAME}.{table} after {elapsed:.1f}s: {error}")
                    raise error
                log.info(f"Set {mode} on {SCHEMA_NAME}.{table} in {elapsed:.1f}s")

    total_elapsed = perf_counter() - start_time
    log.info(f"All {len(all_tables)} tables converted to {mode} in {total_elapsed:.1f}s")


def execute_sql_script(query_executor, path_to_script):
    """Load and execute sql script from file
    Params:
      query_executor - callable to execute query with
      path_to_script - path to script
    Returns:
      depending on query_executor

    Example:
      print(execute_sql_script(db.query_row, "./test.sql"))
      where test_sql: SELECT * FROM hive_state WHERE block_num = 0;
      will return something like: (0, 18, Decimal('0.000000'), Decimal('0.000000'), Decimal('0.000000'), '')
    """
    try:
        sql_script = None
        with open(path_to_script) as sql_script_file:
            sql_script = sql_script_file.read()
        if sql_script is not None:
            return query_executor(sql_script)
    except Exception as ex:
        log.exception(f"Error running sql script: {ex}")
        raise ex
    return None
