do $$
BEGIN
   ASSERT EXISTS (SELECT * FROM pg_extension WHERE extname='intarray'), 'The database requires created "intarray" extension';
END$$;

CREATE TABLE IF NOT EXISTS hive_db_patch_level
(
  level SERIAL NOT NULL PRIMARY KEY,
  patch_date timestamp without time zone NOT NULL,
  patched_to_revision TEXT
);

CREATE TABLE IF NOT EXISTS hive_db_data_migration
(
  migration varchar(128) not null
);

CREATE TABLE IF NOT EXISTS hive_db_vacuum_needed
(
  vacuum_needed BOOLEAN NOT NULL
);

TRUNCATE TABLE hive_db_vacuum_needed;

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

SHOW join_collapse_limit;
SHOW from_collapse_limit;

####################################### 1.26 release upgrades #######################################

--- Begin changes done in MR https://gitlab.syncad.com/hive/hivemind/-/merge_requests/574

--- Changes done in index hive_posts_community_id_id_idx overwritted by MR 575 (see below)

DROP INDEX IF EXISTS hive_posts_community_id_is_pinned_idx;

CREATE INDEX IF NOT EXISTS hive_posts_community_id_is_pinned_idx
    ON public.hive_posts USING btree
    (community_id ASC NULLS LAST)
    INCLUDE(id)
    WHERE is_pinned AND counter_deleted = 0;

--- End of MR https://gitlab.syncad.com/hive/hivemind/-/merge_requests/574

--- Begin of MR https://gitlab.syncad.com/hive/hivemind/-/merge_requests/575 --- 

DROP INDEX IF EXISTS hive_posts_community_id_id_idx;

CREATE INDEX IF NOT EXISTS hive_posts_community_id_id_idx
    ON public.hive_posts USING btree
    (community_id ASC NULLS LAST, id DESC)
    WHERE counter_deleted = 0
    ;

--- dedicated to bridge_get_ranked_post_by_created_for_community
CREATE INDEX IF NOT EXISTS hive_posts_community_id_not_is_pinned_idx
  ON public.hive_posts USING btree
  (community_id, id DESC)
  WHERE NOT is_pinned and depth = 0 and counter_deleted = 0
  ;

--- Specific to bridge_get_ranked_post_by_trends_for_community
CREATE INDEX IF NOT EXISTS hive_posts_community_id_not_is_paidout_idx
  ON public.hive_posts USING btree
  (community_id)
  INCLUDE (id)
  WHERE NOT is_paidout AND depth = 0 AND counter_deleted = 0
  ;

DROP INDEX IF EXISTS hive_posts_author_id_id_idx;

CREATE INDEX IF NOT EXISTS hive_posts_author_id_id_idx
  ON public.hive_posts USING btree
  (author_id, id DESC)
  WHERE counter_deleted = 0
  ;

DROP INDEX IF EXISTS hive_follows_following_state_idx;

CREATE INDEX IF NOT EXISTS hive_follows_following_state_idx
  ON public.hive_follows USING btree
  (following, state)
  ;

DROP INDEX IF EXISTS hive_follows_follower_state_idx;

CREATE INDEX IF NOT EXISTS hive_follows_follower_state_idx
  ON public.hive_follows USING btree
  (follower, state)
  ;

DROP INDEX IF EXISTS hive_follows_follower_following_state_idx;

CREATE INDEX IF NOT EXISTS hive_follows_follower_following_state_idx
  ON public.hive_follows USING btree
  (follower, following, state)
  ;

DROP INDEX IF EXISTS hive_feed_cache_account_id_created_at_post_id_idx;

--- Dedicated index to bridge_get_account_posts_by_blog
CREATE INDEX IF NOT EXISTS hive_feed_cache_account_id_created_at_post_id_idx
  ON public.hive_feed_cache
  (account_id, created_at DESC, post_id DESC)
  ;

--- End of MR https://gitlab.syncad.com/hive/hivemind/-/merge_requests/575 --- 
