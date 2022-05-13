"""Db schema definitions and setup routines."""

import logging
from pathlib import Path

from hive.conf import SCHEMA_NAME

log = logging.getLogger(__name__)

# pylint: disable=line-too-long, too-many-lines, bad-whitespace
recreate_fks_queries = []


def drop_fk(db):
    global recreate_fks_queries
    recreate_fks_queries = db.query_col(f"SELECT {SCHEMA_NAME}.get_add_fks_queries();")

    queries_to_drop_fks = db.query_col(f"SELECT {SCHEMA_NAME}.get_drop_fks_queries();")
    for sql in queries_to_drop_fks:
        db.query(sql)


def create_fk(db):
    from sqlalchemy import text

    global recreate_fks_queries

    connection = db.get_new_connection('create_fk')
    connection.execute(text("START TRANSACTION"))
    for sql in recreate_fks_queries:
        connection.execute(sql)
    connection.execute(text("COMMIT"))


def setup(db):
    """Creates all tables and seed data"""

    sql = """SELECT * FROM pg_extension WHERE extname='intarray'"""
    assert db.query_row(sql), "The database requires created 'intarray' extension"

    sql_scripts_dir_path = Path(__file__).parent / 'sql_scripts'

    # create schema and aux functions
    execute_sql_script(query_executor=db.query_no_return, path_to_script=sql_scripts_dir_path / 'schema.sql')

    # initialize schema
    db.query_no_return(f"CALL {SCHEMA_NAME}.define_schema();")

    # tune auto vacuum/analyze
    reset_autovac(db)

    # sets FILLFACTOR:
    set_fillfactor(db)

    # default rows
    db.query_no_return(f"CALL {SCHEMA_NAME}.populate_with_defaults();")

    sql = f"CREATE INDEX hive_communities_ft1 ON {SCHEMA_NAME}.hive_communities USING GIN (to_tsvector('english', title || ' ' || about))"
    db.query(sql)

    # find_comment_id definition moved to utility_functions.sql
    # find_account_id definition moved to utility_functions.sql

    # process_hive_post_operation definition moved to hive_post_operations.sql
    # delete_hive_post moved to hive_post_operations.sql

    # In original hivemind, a value of 'active_at' was calculated from
    # max
    #   {
    #     created             ( account_create_operation ),
    #     last_account_update ( account_update_operation/account_update2_operation ),
    #     last_post           ( comment_operation - only creation )
    #     last_root_post      ( comment_operation - only creation + only ROOT ),
    #     last_vote_time      ( vote_operation )
    #   }
    # In order to simplify calculations, `last_account_update` is not taken into consideration, because this updating accounts is very rare
    # and posting/voting after an account updating, fixes `active_at` value immediately.

    # hive_accounts_view definition moved to hive_accounts_view.sql

    # hive_posts_view definition moved to hive_posts_view.sql

    # update_hive_posts_root_id moved to update_hive_posts_root_id.sql

    # hive_votes_view definition moved into hive_votes_view.sql

    # database_api_vote, find_votes, list_votes_by_voter_comment, list_votes_by_comment_voter moved into database_api_list_votes.sql

    sql = """
          DO $$
          DECLARE
          __version INT;
          BEGIN
            SELECT CURRENT_SETTING('server_version_num')::INT INTO __version;

            EXECUTE 'ALTER DATABASE '||current_database()||' SET join_collapse_limit TO 16';
            EXECUTE 'ALTER DATABASE '||current_database()||' SET from_collapse_limit TO 16';

            IF __version >= 120000 THEN
              RAISE NOTICE 'Disabling a JIT optimization on the current database level...';
              EXECUTE 'ALTER DATABASE '||current_database()||' SET jit TO False';
            END IF;
          END
          $$;
          """
    db.query_no_return(sql)

    sql = f"""
          CREATE TABLE IF NOT EXISTS {SCHEMA_NAME}.hive_db_patch_level
          (
            level SERIAL NOT NULL PRIMARY KEY,
            patch_date timestamp without time zone NOT NULL,
            patched_to_revision TEXT
          );
    """
    db.query_no_return(sql)

    # max_time_stamp definition moved into utility_functions.sql

    # get_discussion definition moved to bridge_get_discussion.sql

    sql_scripts = [
        "utility_functions.sql",
        "hive_accounts_view.sql",
        "hive_accounts_info_view.sql",
        "hive_posts_base_view.sql",
        "hive_posts_view.sql",
        "hive_votes_view.sql",
        "hive_muted_accounts_view.sql",
        "hive_muted_accounts_by_id_view.sql",
        "hive_blacklisted_accounts_by_observer_view.sql",
        "get_post_view_by_id.sql",
        "hive_post_operations.sql",
        "head_block_time.sql",
        "update_feed_cache.sql",
        "payout_stats_view.sql",
        "update_hive_posts_mentions.sql",
        "mutes.sql",
        "bridge_get_ranked_post_type.sql",
        "bridge_get_ranked_post_for_communities.sql",
        "bridge_get_ranked_post_for_observer_communities.sql",
        "bridge_get_ranked_post_for_tag.sql",
        "bridge_get_ranked_post_for_all.sql",
        "calculate_account_reputations.sql",
        "update_communities_rank.sql",
        "delete_hive_posts_mentions.sql",
        "notifications_view.sql",
        "notifications_api.sql",
        "bridge_get_account_posts_by_comments.sql",
        "bridge_get_account_posts_by_payout.sql",
        "bridge_get_account_posts_by_posts.sql",
        "bridge_get_account_posts_by_replies.sql",
        "bridge_get_relationship_between_accounts.sql",
        "bridge_get_post.sql",
        "bridge_get_discussion.sql",
        "condenser_api_post_type.sql",
        "condenser_api_post_ex_type.sql",
        "condenser_get_blog.sql",
        "condenser_get_content.sql",
        "condenser_tags.sql",
        "condenser_follows.sql",
        "hot_and_trends.sql",
        "update_hive_posts_children_count.sql",
        "update_hive_posts_api_helper.sql",
        "database_api_list_comments.sql",
        "database_api_list_votes.sql",
        "update_posts_rshares.sql",
        "update_hive_post_root_id.sql",
        "condenser_get_by_account_comments.sql",
        "condenser_get_by_blog_without_reblog.sql",
        "bridge_get_by_feed_with_reblog.sql",
        "condenser_get_by_blog.sql",
        "bridge_get_account_posts_by_blog.sql",
        "condenser_get_names_by_reblogged.sql",
        "condenser_get_account_reputations.sql",
        "bridge_get_community.sql",
        "bridge_get_community_context.sql",
        "bridge_list_all_subscriptions.sql",
        "bridge_list_communities.sql",
        "bridge_list_community_roles.sql",
        "bridge_list_pop_communities.sql",
        "bridge_list_subscribers.sql",
        "update_follow_count.sql",
        "delete_reblog_feed_cache.sql",
        "follows.sql",
        "is_superuser.sql",
        "update_hive_blocks_consistency_flag.sql",
        "update_table_statistics.sql",
        "upgrade/update_db_patchlevel.sql",
        # Additionally execute db patchlevel import to mark (already done) upgrade changes and avoid its reevaluation during next upgrade.
    ]

    for script in sql_scripts:
        execute_sql_script(db.query_no_return, sql_scripts_dir_path / script)

    # Move this part here, to mark latest db patch level as current Hivemind revision (which just created schema).
    sql = f"""
          INSERT INTO {SCHEMA_NAME}.hive_db_patch_level
          (patch_date, patched_to_revision)
          values
          (now(), '{{}}');
          """

    from hive.version import GIT_REVISION

    db.query_no_return(sql.format(GIT_REVISION))


def reset_autovac(db):
    """Initializes/resets per-table autovacuum/autoanalyze params.

    We use a scale factor of 0 and specify exact threshold tuple counts,
    per-table, in the format (autovacuum_threshold, autoanalyze_threshold)."""

    autovac_config = {  # vacuum  analyze
        'hive_accounts': (50000, 100000),
        'hive_posts': (2500, 10000),
        'hive_follows': (5000, 5000),
        'hive_feed_cache': (5000, 5000),
        'hive_blocks': (5000, 25000),
        'hive_reblogs': (5000, 5000),
        'hive_payments': (5000, 5000),
    }

    for table, (n_vacuum, n_analyze) in autovac_config.items():
        sql = f"""
ALTER TABLE {SCHEMA_NAME}.{table} SET (autovacuum_vacuum_scale_factor = 0,
                                  autovacuum_vacuum_threshold = {n_vacuum},
                                  autovacuum_analyze_scale_factor = 0,
                                  autovacuum_analyze_threshold = {n_analyze});
"""
        db.query(sql)


def set_fillfactor(db):
    """Initializes/resets FILLFACTOR for tables which are intesively updated"""

    fillfactor_config = {'hive_posts': 70, 'hive_post_data': 70, 'hive_votes': 70, 'hive_reputation_data': 50}

    for table, fillfactor in fillfactor_config.items():
        sql = f"ALTER TABLE {SCHEMA_NAME}.{table} SET (FILLFACTOR = {fillfactor});"
        db.query(sql)


def set_logged_table_attribute(db, logged):
    """Initializes/resets LOGGED/UNLOGGED attribute for tables which are intesively updated"""

    logged_config = [
        'hive_accounts',
        'hive_permlink_data',
        'hive_posts',
        'hive_post_data',
        'hive_votes',
        'hive_reputation_data',
    ]

    for table in logged_config:
        log.info(f"Setting {'LOGGED' if logged else 'UNLOGGED'} attribute on a table: {table}")
        sql = """ALTER TABLE {} SET {}"""
        db.query_no_return(sql.format(table, 'LOGGED' if logged else 'UNLOGGED'))


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
        with open(path_to_script, 'r') as sql_script_file:
            sql_script = sql_script_file.read()
        if sql_script is not None:
            return query_executor(sql_script)
    except Exception as ex:
        log.exception(f"Error running sql script: {ex}")
        raise ex
    return None
