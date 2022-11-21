do $$
BEGIN
  ASSERT EXISTS (SELECT * FROM pg_extension WHERE extname='intarray'), 'The database requires created "intarray" extension';
  ASSERT (SELECT setting FROM pg_settings where name='join_collapse_limit' and source='database')::int = 16, 'Bad optimizer settings, use setup_db.sh script to setup target database correctly';
  ASSERT (SELECT setting FROM pg_settings where name='from_collapse_limit' and source='database')::int = 16, 'Bad optimizer settings, use setup_db.sh script to setup target database correctly';
  ASSERT (SELECT setting FROM pg_settings where name='jit' and source='database')::BOOLEAN = False, 'Bad optimizer settings, use setup_db.sh script to setup target database correctly';
END$$;

CREATE TABLE IF NOT EXISTS hivemind_app.hive_db_patch_level
(
  level SERIAL NOT NULL PRIMARY KEY,
  patch_date timestamp without time zone NOT NULL,
  patched_to_revision TEXT
);

CREATE TABLE IF NOT EXISTS hivemind_app.hive_db_data_migration
(
  migration varchar(128) not null
);

CREATE TABLE IF NOT EXISTS hivemind_app.hive_db_vacuum_needed
(
  vacuum_needed BOOLEAN NOT NULL
);

TRUNCATE TABLE hivemind_app.hive_db_vacuum_needed;

--- Put schema upgrade code here.

--- ####################################### 1.26 release upgrades #######################################

--- Begin changes done in MR https://gitlab.syncad.com/hive/hivemind/-/merge_requests/574

--- Changes done in index hive_posts_community_id_id_idx overwritted by MR 575 (see below)

DROP INDEX IF EXISTS hivemind_app.hive_posts_community_id_is_pinned_idx;

CREATE INDEX IF NOT EXISTS hivemind_app.hive_posts_community_id_is_pinned_idx
    ON hivemind_app.hive_posts USING btree
    (community_id ASC NULLS LAST)
    INCLUDE(id)
    WHERE is_pinned AND counter_deleted = 0;

--- End of MR https://gitlab.syncad.com/hive/hivemind/-/merge_requests/574

--- Begin of MR https://gitlab.syncad.com/hive/hivemind/-/merge_requests/575 --- 

DROP INDEX IF EXISTS hivemind_app.hive_posts_community_id_id_idx;

CREATE INDEX IF NOT EXISTS hivemind_app.hive_posts_community_id_id_idx
    ON hivemind_app.hive_posts USING btree
    (community_id ASC NULLS LAST, id DESC)
    WHERE counter_deleted = 0
    ;

--- dedicated to bridge_get_ranked_post_by_created_for_community
CREATE INDEX IF NOT EXISTS hivemind_app.hive_posts_community_id_not_is_pinned_idx
  ON hivemind_app.hive_posts USING btree
  (community_id, id DESC)
  WHERE NOT is_pinned and depth = 0 and counter_deleted = 0
  ;

--- Specific to bridge_get_ranked_post_by_trends_for_community
CREATE INDEX IF NOT EXISTS hivemind_app.hive_posts_community_id_not_is_paidout_idx
  ON hivemind_app.hive_posts USING btree
  (community_id)
  INCLUDE (id)
  WHERE NOT is_paidout AND depth = 0 AND counter_deleted = 0
  ;

DROP INDEX IF EXISTS hivemind_app.hive_posts_author_id_id_idx;

CREATE INDEX IF NOT EXISTS hivemind_app.hive_posts_author_id_id_idx
  ON hivemind_app.hive_posts USING btree
  (author_id, id DESC)
  WHERE counter_deleted = 0
  ;

DROP INDEX IF EXISTS hivemind_app.hive_follows_following_state_idx;

CREATE INDEX IF NOT EXISTS hivemind_app.hive_follows_following_state_idx
  ON hivemind_app.hive_follows USING btree
  (following, state)
  ;

DROP INDEX IF EXISTS hivemind_app.hive_follows_follower_state_idx;

CREATE INDEX IF NOT EXISTS hivemind_app.hive_follows_follower_state_idx
  ON hivemind_app.hive_follows USING btree
  (follower, state)
  ;

DROP INDEX IF EXISTS hivemind_app.hive_follows_follower_following_state_idx;

CREATE INDEX IF NOT EXISTS hivemind_app.hive_follows_follower_following_state_idx
  ON hivemind_app.hive_follows USING btree
  (follower, following, state)
  ;

DROP INDEX IF EXISTS hivemind_app.hive_feed_cache_account_id_created_at_post_id_idx;

--- Dedicated index to bridge_get_account_posts_by_blog
CREATE INDEX IF NOT EXISTS hivemind_app.hive_feed_cache_account_id_created_at_post_id_idx
  ON hivemind_app.hive_feed_cache
  (account_id, created_at DESC, post_id DESC)
  ;

--- End of MR https://gitlab.syncad.com/hive/hivemind/-/merge_requests/575 --- 

