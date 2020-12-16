"""Hive db state manager. Check if schema loaded, init synced, etc."""

#pylint: disable=too-many-lines

import time
from time import perf_counter

import logging
import sqlalchemy

from hive.db.schema import (setup, set_logged_table_attribute, build_metadata,
                            build_metadata_community, teardown)
from hive.db.adapter import Db

from concurrent.futures import ThreadPoolExecutor, as_completed

from hive.utils.post_active import update_active_starting_from_posts_on_block
from hive.utils.communities_rank import update_communities_posts_and_rank

from hive.server.common.payout_stats import PayoutStats

log = logging.getLogger(__name__)

SYNCED_BLOCK_LIMIT = 7*24*1200 # 7 days

class DbState:
    """Manages database state: sync status, migrations, etc."""

    _db = None

    # prop is true until initial sync complete
    _is_initial_sync = True

    @classmethod
    def initialize(cls):
        """Perform startup database checks.

        1) Load schema if needed
        2) Run migrations if needed
        3) Check if initial sync has completed
        """

        log.info("[INIT] Welcome to hive!")

        # create db schema if needed
        if not cls._is_schema_loaded():
            log.info("[INIT] Create db schema...")
            setup(cls.db())

        # check if initial sync complete
        cls._is_initial_sync = True
        log.info("[INIT] Continue with initial sync...")

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
    def finish_initial_sync(cls, current_imported_block):
        """Set status to initial sync complete."""
        assert cls._is_initial_sync, "initial sync was not started."
        cls._after_initial_sync(current_imported_block)
        cls._is_initial_sync = False
        log.info("[INIT] Initial sync complete!")

    @classmethod
    def is_initial_sync(cls):
        """Check if we're still in the process of initial sync."""
        return cls._is_initial_sync

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
            'hive_blocks_created_at_idx',

            'hive_feed_cache_block_num_idx',
            'hive_feed_cache_created_at_idx',
            'hive_feed_cache_post_id_idx',

            'hive_follows_ix5a', # (following, state, created_at, follower)
            'hive_follows_ix5b', # (follower, state, created_at, following)
            'hive_follows_block_num_idx',
            'hive_follows_created_at_idx',

            'hive_posts_parent_id_id_idx',
            'hive_posts_depth_idx',
            'hive_posts_root_id_id_idx',

            'hive_posts_community_id_id_idx',
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
            'hive_notification_cache_dst_score_idx'
        ]

        to_return = {}
        md = build_metadata()
        for table in md.tables.values():
            for index in table.indexes:
                if index.name not in to_locate:
                    continue
                to_locate.remove(index.name)
                if table not in to_return:
                  to_return[ table ] = []
                to_return[ table ].append(index)

        # ensure we found all the items we expected
        assert not to_locate, "indexes not located: {}".format(to_locate)
        return to_return

    @classmethod
    def has_index(cls, idx_name):
        sql = "SELECT count(*) FROM pg_class WHERE relname = :relname"
        count = cls.db().query_one(sql, relname=idx_name)
        if count == 1:
            return True
        else:
            return False

    @classmethod
    def _execute_query(cls, db, query):
        time_start = perf_counter()
   
        current_work_mem = cls.update_work_mem('2GB')
        log.info("[INIT] Attempting to execute query: `%s'...", query)

        row = db.query_no_return(query)

        cls.update_work_mem(current_work_mem)

        time_end = perf_counter()
        log.info("[INIT] Query `%s' done in %.4fs", query, time_end - time_start)


    @classmethod
    def processing_indexes_per_table(cls, db, indexes, is_pre_process, drop, create):
        log.info("[INIT] Begin %s-initial sync hooks", "pre" if is_pre_process else "post")
        engine = db.engine()

        any_index_created = False

        for index in indexes:
            log.info("%s index %s.%s", ("Drop" if is_pre_process else "Recreate"), index.table, index.name)
            try:
                if drop:
                    if cls.has_index(index.name):
                        time_start = perf_counter()
                        index.drop(engine)
                        end_time = perf_counter()
                        elapsed_time = end_time - time_start
                        log.info("Index %s dropped in time %.4f s", index.name, elapsed_time)
            except sqlalchemy.exc.ProgrammingError as ex:
                log.warning("Ignoring ex: {}".format(ex))

            if create:
                if cls.has_index(index.name):
                    log.info("Index %s already exists... Creation skipped.", index.name)
                else:
                    time_start = perf_counter()
                    index.create(engine)
                    end_time = perf_counter()
                    elapsed_time = end_time - time_start
                    log.info("Index %s created in time %.4f s", index.name, elapsed_time)
                    any_index_created = True
        if any_index_created:
            cls._execute_query(db,"ANALYZE")

    @classmethod
    def processing_indexes(cls, is_pre_process, drop, create):
        _indexes = cls._disableable_indexes()
        futures = []
        with ThreadPoolExecutor(max_workers=len(_indexes)) as executor:
            for _key_table, indexes in _indexes.items():
              futures.append( executor.submit(cls.processing_indexes_per_table, cls.db().clone(), indexes, is_pre_process, drop, create) )

            completedThreads = 0
            for future in as_completed(futures):
              completedThreads = completedThreads + 1
            log.info("[INIT] Completed threads during indexes processing: %i", completedThreads)

    @classmethod
    def before_initial_sync(cls, last_imported_block, hived_head_block):
        """Routine which runs *once* after db setup.

        Disables non-critical indexes for faster initial sync, as well
        as foreign key constraints."""

        to_sync = hived_head_block - last_imported_block

        if to_sync < SYNCED_BLOCK_LIMIT:
            log.info("[INIT] Skipping pre-initial sync hooks")
            return

        #is_pre_process, drop, create
        cls.processing_indexes( True, True, False )

        from hive.db.schema import drop_fk, set_logged_table_attribute
        log.info("Dropping FKs")
        drop_fk(cls.db())

        # intentionally disabled since it needs a lot of WAL disk space when switching back to LOGGED
        #set_logged_table_attribute(cls.db(), False)

        log.info("[INIT] Finish pre-initial sync hooks")

    @classmethod
    def update_work_mem(cls, workmem_value):
        row = cls.db().query_row("SHOW work_mem")
        current_work_mem = row['work_mem']

        sql = """
              DO $$
              BEGIN
                EXECUTE 'ALTER DATABASE '||current_database()||' SET work_mem TO "{}"';
              END
              $$;
              """
        cls.db().query_no_return(sql.format(workmem_value))

        return current_work_mem

    @classmethod
    def _after_initial_sync(cls, current_imported_block):
        """Routine which runs *once* after initial sync.

        Re-creates non-core indexes for serving APIs after init sync,
        as well as all foreign keys."""

        start_time = perf_counter()

        last_imported_block = DbState.db().query_one("SELECT block_num FROM hive_state LIMIT 1")

        log.info("[INIT] Current imported block: %s. Last imported block: %s.", current_imported_block, last_imported_block)
        if last_imported_block > current_imported_block:
          last_imported_block = current_imported_block

        synced_blocks = current_imported_block - last_imported_block

        force_index_rebuild = False
        massive_sync_preconditions = False
        if synced_blocks >= SYNCED_BLOCK_LIMIT:
            force_index_rebuild = True
            massive_sync_preconditions = True

    def _finish_hive_posts(cls, db, massive_sync_preconditions, last_imported_block, current_imported_block):
        def vacuum_hive_posts(cls):
          if massive_sync_preconditions:
              cls._execute_query(db, "VACUUM ANALYZE hive_posts")

        #UPDATE: `children`
        time_start = perf_counter()
        if massive_sync_preconditions:
            # Update count of all child posts (what was hold during initial sync)
            cls._execute_query(db, "select update_all_hive_posts_children_count()")
        else:
            # Update count of child posts processed during partial sync (what was hold during initial sync)
            sql = "select update_hive_posts_children_count({}, {})".format(last_imported_block, current_imported_block)
            cls._execute_query(db, sql)
        log.info("[INIT] update_hive_posts_children_count executed in %.4fs", perf_counter() - time_start)

        time_start = perf_counter()
        vacuum_hive_posts(cls)
        log.info("[INIT] VACUUM ANALYZE hive_posts executed in %.4fs", perf_counter() - time_start)

        #UPDATE: `root_id`
        # Update root_id all root posts
        time_start = perf_counter()
        sql = """
              select update_hive_posts_root_id({}, {})
              """.format(last_imported_block, current_imported_block)
        cls._execute_query(db, sql)
        log.info("[INIT] update_hive_posts_root_id executed in %.4fs", perf_counter() - time_start)

        time_start = perf_counter()
        vacuum_hive_posts(cls)
        log.info("[INIT] VACUUM ANALYZE hive_posts executed in %.4fs", perf_counter() - time_start)

        #UPDATE: `active`
        time_start = perf_counter()
        update_active_starting_from_posts_on_block(last_imported_block, current_imported_block)
        log.info("[INIT] update_all_posts_active executed in %.4fs", perf_counter() - time_start)

        time_start = perf_counter()
        vacuum_hive_posts(cls)
        log.info("[INIT] VACUUM ANALYZE hive_posts executed in %.4fs", perf_counter() - time_start)

        #UPDATE: `abs_rshares`, `vote_rshares`, `sc_hot`, ,`sc_trend`, `total_votes`, `net_votes`
        time_start = perf_counter()
        sql = """
              SELECT update_posts_rshares({}, {});
              """.format(last_imported_block, current_imported_block)
        cls._execute_query(db, sql)
        log.info("[INIT] update_posts_rshares executed in %.4fs", perf_counter() - time_start)

        time_start = perf_counter()
        vacuum_hive_posts(cls)
        log.info("[INIT] VACUUM ANALYZE hive_posts executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_hive_posts_api_helper(cls, db, last_imported_block, current_imported_block):
        time_start = perf_counter()
        sql = """
              select update_hive_posts_api_helper({}, {})
              """.format(last_imported_block, current_imported_block)
        cls._execute_query(db, sql)
        log.info("[INIT] update_hive_posts_api_helper executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_hive_feed_cache(cls, db, last_imported_block, current_imported_block):
        time_start = perf_counter()
        sql = """
            SELECT update_feed_cache({}, {});
        """.format(last_imported_block, current_imported_block)
        cls._execute_query(db, sql)
        log.info("[INIT] update_feed_cache executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_hive_mentions(cls, db, last_imported_block, current_imported_block):
        time_start = perf_counter()
        sql = """
            SELECT update_hive_posts_mentions({}, {});
        """.format(last_imported_block, current_imported_block)
        cls._execute_query(db, sql)
        log.info("[INIT] update_hive_posts_mentions executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_payout_stats_view(cls):
        time_start = perf_counter()
        PayoutStats.generate()
        log.info("[INIT] payout_stats_view executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_account_reputations(cls, db, last_imported_block, current_imported_block):
        time_start = perf_counter()
        sql = """
              SELECT update_account_reputations({}, {}, True);
              """.format(last_imported_block, current_imported_block)
        cls._execute_query(db, sql)
        log.info("[INIT] update_account_reputations executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_communities_posts_and_rank(cls, db):
        time_start = perf_counter()
        update_communities_posts_and_rank(db)
        log.info("[INIT] update_communities_posts_and_rank executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_notification_cache(cls, db):
        time_start = perf_counter()
        sql = """
              SELECT update_notification_cache(NULL, NULL, False);
              """
        cls._execute_query(db, sql)
        log.info("[INIT] update_notification_cache executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_follow_count(cls, db, last_imported_block, current_imported_block):
        time_start = perf_counter()
        sql = """
              SELECT update_follow_count({}, {});
              """.format(last_imported_block, current_imported_block)
        cls._execute_query(db, sql)
        log.info("[INIT] update_follow_count executed in %.4fs", perf_counter() - time_start)

    @classmethod
    def _finish_all_tables(cls, massive_sync_preconditions, last_imported_block, current_imported_block):
        futures = []
        with ThreadPoolExecutor(max_workers=7) as executor:
          futures.append( executor.submit(cls._finish_hive_posts, cls.db().clone(), massive_sync_preconditions, last_imported_block, current_imported_block) )
          futures.append( executor.submit(cls._finish_hive_feed_cache, cls.db().clone(), last_imported_block, current_imported_block) )
          futures.append( executor.submit(cls._finish_hive_mentions, cls.db().clone(), last_imported_block, current_imported_block) )
          futures.append( executor.submit(cls._finish_payout_stats_view) )
          futures.append( executor.submit(cls._finish_account_reputations, cls.db().clone(), last_imported_block, current_imported_block) )
          futures.append( executor.submit(cls._finish_communities_posts_and_rank, cls.db().clone()) )
          futures.append( executor.submit(cls._finish_follow_count, cls.db().clone(), last_imported_block, current_imported_block) )

          completedThreads = 0
          for future in as_completed(futures):
            completedThreads = completedThreads + 1
          log.info("[INIT] Completed threads during tables `part 1` processing: %i. ", completedThreads)

        futures = []
        with ThreadPoolExecutor(max_workers=2) as executor:
          #Notifications are dependent on many tables, therefore it's necessary to calculate it at the end
          futures.append( executor.submit(cls._finish_notification_cache, cls.db().clone() ) )
          #hive_posts_api_helper is dependent on `hive_posts/root_id` filling
          futures.append( executor.submit(cls._finish_hive_posts_api_helper, cls.db().clone(), last_imported_block, current_imported_block) )

          completedThreads = 0
          for future in as_completed(futures):
            completedThreads = completedThreads + 1
          log.info("[INIT] Completed threads during tables `part 2` processing: %i. ", completedThreads)

    @classmethod
    def _after_initial_sync(cls, current_imported_block):
        """Routine which runs *once* after initial sync.

        Re-creates non-core indexes for serving APIs after init sync,
        as well as all foreign keys."""

        last_imported_block = DbState.db().query_one("SELECT block_num FROM hive_state LIMIT 1")

        log.info("[INIT] Current imported block: %s. Last imported block: %s.", current_imported_block, last_imported_block)
        if last_imported_block > current_imported_block:
          last_imported_block = current_imported_block

        synced_blocks = current_imported_block - last_imported_block

        force_index_rebuild = False
        massive_sync_preconditions = False
        if synced_blocks >= SYNCED_BLOCK_LIMIT:
            force_index_rebuild = True
            massive_sync_preconditions = True

        #is_pre_process, drop, create
        cls.processing_indexes( False, force_index_rebuild, True )

        #all post-updates are executed in different threads: one thread per one table
        cls._finish_all_tables(massive_sync_preconditions, last_imported_block, current_imported_block)

        # Update a block num immediately
        cls.db().query_no_return("UPDATE hive_state SET block_num = :block_num", block_num = current_imported_block)

        if massive_sync_preconditions:
            from hive.db.schema import create_fk, set_logged_table_attribute
            # intentionally disabled since it needs a lot of WAL disk space when switching back to LOGGED
            #set_logged_table_attribute(cls.db(), True)

            log.info("Recreating FKs")
            create_fk(cls.db())

            cls._execute_query(cls.db(),"VACUUM ANALYZE")

        end_time = perf_counter()
        log.info("[INIT] After initial sync actions done in %.4fs", end_time - start_time)


    @staticmethod
    def status():
        """Basic health status: head block/time, current age (secs)."""
        sql = ("SELECT num, created_at, extract(epoch from created_at) ts "
               "FROM hive_blocks ORDER BY num DESC LIMIT 1")
        row = DbState.db().query_row(sql)
        return dict(db_head_block=row['num'],
                    db_head_time=str(row['created_at']),
                    db_head_age=int(time.time() - row['ts']))

    @classmethod
    def _is_schema_loaded(cls):
        """Check if the schema has been loaded into db yet."""
        # check if database has been initialized (i.e. schema loaded)
        engine = cls.db().engine_name()
        if engine == 'postgresql':
            return bool(cls.db().query_one("""
                SELECT 1 FROM pg_catalog.pg_tables WHERE schemaname = 'public'
            """))
        if engine == 'mysql':
            return bool(cls.db().query_one('SHOW TABLES'))
        raise Exception("unknown db engine %s" % engine)

    @classmethod
    def _is_feed_cache_empty(cls):
        """Check if the hive_feed_cache table is empty.

        If empty, it indicates that the initial sync has not finished.
        """
        return not cls.db().query_one("SELECT 1 FROM hive_feed_cache LIMIT 1")

