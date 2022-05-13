do $$
BEGIN
   ASSERT EXISTS (SELECT * FROM pg_extension WHERE extname='intarray'), 'The database requires created "intarray" extension';
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

DO
$BODY$
BEGIN
IF NOT EXISTS(SELECT data_type
              FROM information_schema.columns
              WHERE table_name = 'hive_accounts' AND column_name = 'is_implicit') THEN
    RAISE NOTICE 'Performing hivemind_app.hive_accounts upgrade - adding new column is_implicit';
    PERFORM hivemind_app.deps_save_and_drop_dependencies('public', 'hive_accounts', true);
    alter table ONlY hivemind_app.hive_accounts
      add column is_implicit boolean,
      alter column is_implicit set default True;

    --- reputations have to be recalculated from scratch.
    update hivemind_app.hive_accounts set reputation = 0, is_implicit = True;

    alter table ONlY hivemind_app.hive_accounts
      alter column is_implicit set not null;

    PERFORM hivemind_app.deps_restore_dependencies('public', 'hive_accounts');

    INSERT INTO hivemind_app.hive_db_data_migration VALUES ('Reputation calculation');
ELSE
  RAISE NOTICE 'hive_accounts::is_implicit migration skipped';
END IF;

IF EXISTS(SELECT data_type
          FROM information_schema.columns
          WHERE table_name = 'hive_accounts' AND column_name = 'blacklist_description') THEN
    RAISE NOTICE 'Performing hivemind_app.hive_accounts upgrade - removing columns blacklist_description/muted_list_description';
    -- drop hivemind_app.hive_accounts_info_view since it uses removed column. It will be rebuilt after upgrade
    DROP VIEW IF EXISTS hivemind_app.hive_accounts_info_view;

    PERFORM hivemind_app.deps_save_and_drop_dependencies('public', 'hive_accounts', true);
    ALTER TABLE ONlY hivemind_app.hive_accounts
      DROP COLUMN IF EXISTS hivemind_app.blacklist_description,
      DROP COLUMN IF EXISTS hivemind_app.muted_list_description
      ;
ELSE
  RAISE NOTICE 'hive_accounts::blacklist_description/muted_list_description migration skipped';
END IF;

END
$BODY$;

DROP TABLE IF EXISTS hivemind_app.hive_account_reputation_status;

drop index IF EXISTS hivemind_app.hive_posts_sc_hot_idx;
drop index IF EXISTS hivemind_app.hive_posts_sc_trend_idx;
drop index IF EXISTS hivemind_app.hive_reblogs_blogger_id;
drop index IF EXISTS hivemind_app.hive_subscriptions_community_idx;
drop index IF EXISTS hivemind_app.hive_votes_post_id_idx;
drop index IF EXISTS hivemind_app.hive_votes_voter_id_idx;
drop index IF EXISTS hivemind_app.hive_votes_last_update_idx;
drop index IF EXISTS hivemind_app.hive_posts_community_id_idx;

CREATE INDEX IF NOT EXISTS hive_posts_cashout_time_id_idx ON hivemind_app.hive_posts (cashout_time, id);
CREATE INDEX IF NOT EXISTS hive_posts_updated_at_idx ON hivemind_app.hive_posts (updated_at DESC);
CREATE INDEX IF NOT EXISTS hive_votes_block_num_idx ON hivemind_app.hive_votes (block_num);
CREATE INDEX IF NOT EXISTS hive_posts_community_id_id_idx ON hivemind_app.hive_posts (community_id, id DESC);

DO
$BODY$
BEGIN
IF NOT EXISTS(SELECT data_type
              FROM information_schema.columns
              WHERE table_name = 'hive_posts_api_helper' AND column_name = 'author_s_permlink') THEN
    RAISE NOTICE 'Performing hivemind_app.hive_posts_api_helper upgrade - adding new column author_s_permlink';
    PERFORM hivemind_app.deps_save_and_drop_dependencies('public', 'hive_posts_api_helper', true);

    DROP INDEX IF EXISTS hivemind_app.hive_posts_api_helper_parent_permlink_or_category;
    DROP TABLE IF EXISTS hivemind_app.hive_posts_api_helper;

    CREATE TABLE hivemind_app.hive_posts_api_helper
    (
        id integer NOT NULL,
        author_s_permlink character varying(275) COLLATE pg_catalog."C" NOT NULL,
        CONSTRAINT hivemind_app.hive_posts_api_helper_pkey PRIMARY KEY (id)
    );

    PERFORM hivemind_app.deps_restore_dependencies('public', 'hive_posts_api_helper');

    CREATE INDEX IF NOT EXISTS hive_posts_api_helper_author_s_permlink_idx ON hivemind_app.hive_posts_api_helper (author_s_permlink);

    INSERT INTO hivemind_app.hive_db_data_migration VALUES ('hive_posts_api_helper fill');
ELSE
  RAISE NOTICE 'hive_posts_api_helper migration skipped';
END IF;
END
$BODY$
;

DO
$BODY$
BEGIN
IF NOT EXISTS(SELECT data_type
              FROM information_schema.columns
              WHERE table_name = 'hive_mentions' AND column_name = 'block_num') THEN
  RAISE NOTICE 'Performing hivemind_app.hive_mentions upgrade - adding new column block_num';

  TRUNCATE TABLE hivemind_app.hive_mentions RESTART IDENTITY;
  PERFORM hivemind_app.deps_save_and_drop_dependencies('public', 'hive_mentions', true);

  ALTER TABLE hivemind_app.hive_mentions
    DROP CONSTRAINT IF EXISTS hivemind_app.hive_mentions_pk,
    ADD COLUMN IF NOT EXISTS id SERIAL,
    ADD COLUMN  IF NOT EXISTS block_num INTEGER,
    ALTER COLUMN id SET NOT NULL,
    ALTER COLUMN block_num SET NOT NULL,
    ADD CONSTRAINT hive_mentions_pk PRIMARY KEY (id);

  PERFORM hivemind_app.deps_restore_dependencies('public', 'hive_mentions');

  INSERT INTO hivemind_app.hive_db_data_migration VALUES ('hive_mentions fill');
ELSE
  ALTER TABLE hivemind_app.hive_mentions
    DROP CONSTRAINT hivemind_app.hive_mentions_ux1;
  ALTER TABLE hivemind_app.hive_mentions
    ADD CONSTRAINT hive_mentions_ux1 UNIQUE (post_id, account_id, block_num);
END IF;
END
$BODY$
;

---------------------------------------------------------------------------------------------------
--                                hivemind_app.hive_posts table migration
---------------------------------------------------------------------------------------------------

DO
$BODY$
BEGIN
IF EXISTS(SELECT data_type
              FROM information_schema.columns
              WHERE table_name = 'hive_posts' AND column_name = 'is_grayed') THEN
  RAISE NOTICE 'Performing hivemind_app.hive_posts upgrade - dropping is_grayed column';

  --- Warning we need to first drop hivemind_app.hive_posts view since it references column is_grayed, which will be dropped.
  --- Saving it in the dependencies, will restore wrong (old) definition of the view and make an error.
  DROP VIEW IF EXISTS hivemind_app.hive_posts_view CASCADE;

  PERFORM hivemind_app.deps_save_and_drop_dependencies('public', 'hive_posts', true);

  ALTER TABLE hivemind_app.hive_posts
    DROP COLUMN IF EXISTS hivemind_app.is_grayed;

  PERFORM hivemind_app.deps_restore_dependencies('public', 'hive_posts');
ELSE
  RAISE NOTICE 'hive_posts upgrade - SKIPPED dropping is_grayed column';
END IF;

--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/322
IF EXISTS(SELECT data_type FROM information_schema.columns
          WHERE table_name = 'hive_posts' AND column_name = 'abs_rshares' AND data_type = 'bigint') AND
   EXISTS(SELECT data_type FROM information_schema.columns
          WHERE table_name = 'hive_posts' AND column_name = 'vote_rshares' AND data_type = 'bigint') AND
   NOT EXISTS (SELECT data_type FROM information_schema.columns
               WHERE table_name = 'hive_posts' AND column_name = 'block_num_created') THEN
  RAISE NOTICE 'Performing hivemind_app.hive_posts upgrade - adding block_num_created column, type change for abs_rshares/vote_rshares columns';

  PERFORM hivemind_app.deps_save_and_drop_dependencies('public', 'hive_posts', true);

  ALTER TABLE ONLY hivemind_app.hive_posts
    ALTER COLUMN abs_rshares SET DATA TYPE NUMERIC,
    ALTER COLUMN vote_rshares SET DATA TYPE NUMERIC,
    ADD COLUMN block_num_created INTEGER;

    UPDATE hivemind_app.hive_posts SET block_num_created = 1; -- Artificial number, since we don't have this info atm, it requires full sync

    ALTER TABLE ONLY hivemind_app.hive_posts
      ALTER COLUMN block_num_created set not null;

  PERFORM hivemind_app.deps_restore_dependencies('public', 'hive_posts');
ELSE
  RAISE NOTICE 'SKIPPING hivemind_app.hive_posts upgrade - adding a block_num_created column, type change for abs_rshares/vote_rshares columns';
END IF;

--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/367
IF NOT EXISTS (SELECT data_type FROM information_schema.columns
               WHERE table_name = 'hive_posts' AND column_name = 'total_votes')
   AND NOT EXISTS (SELECT data_type FROM information_schema.columns
                 WHERE table_name = 'hive_posts' AND column_name = 'net_votes') THEN
  RAISE NOTICE 'Performing hivemind_app.hive_posts upgrade - adding total_votes and net_votes columns';

  PERFORM hivemind_app.deps_save_and_drop_dependencies('public', 'hive_posts', true);

  ALTER TABLE ONLY hivemind_app.hive_posts
    ADD COLUMN total_votes BIGINT,
    ADD COLUMN net_votes BIGINT;

  UPDATE hivemind_app.hive_posts SET total_votes = 0, net_votes = 0; -- Artificial number, requires to start update_posts_rshares for all blocks

  ALTER TABLE ONLY hivemind_app.hive_posts
    ALTER COLUMN total_votes SET NOT NULL,
    ALTER COLUMN total_votes SET DEFAULT 0,
    ALTER COLUMN net_votes SET NOT NULL,
    ALTER COLUMN net_votes SET DEFAULT 0;

  PERFORM hivemind_app.deps_restore_dependencies('public', 'hive_posts');
ELSE
  RAISE NOTICE 'SKIPPING hivemind_app.hive_posts upgrade - adding total_votes and net_votes columns';
END IF;

IF NOT EXISTS(SELECT data_type FROM information_schema.columns
          WHERE table_name = 'hive_posts' AND column_name = 'tags_ids') THEN
    ALTER TABLE ONLY hivemind_app.hive_posts
            ADD COLUMN tags_ids INTEGER[];

    UPDATE hivemind_app.hive_posts hp
    SET
        tags_ids = tags.tags
    FROM
    (
      SELECT
          post_id as post_id,
          array_agg( hpt.tag_id ) as tags
      FROM
        hivemind_app.hive_post_tags hpt
      GROUP BY post_id
    ) as tags
    WHERE hp.id = tags.post_id;
ELSE
    RAISE NOTICE 'SKIPPING hivemind_app.hive_posts upgrade - adding a tags_ids column';
END IF;

END

$BODY$
;

DROP INDEX IF EXISTS hivemind_app.hive_posts_created_at_idx;
-- skip it since it is dropped below.
-- CREATE INDEX IF NOT EXISTS hive_posts_created_at_author_id_idx ON hivemind_app.hive_posts (created_at, author_id);

CREATE INDEX IF NOT EXISTS hive_posts_block_num_created_idx ON hivemind_app.hive_posts (block_num_created);

DROP INDEX IF EXISTS hivemind_app.hive_mentions_post_id_idx;

-- updated up to 7b8def051be224a5ebc360465f7a1522090c7125
-- updated up to 033619277eccea70118a5b8dc0c73b913da0025f
INSERT INTO hivemind_app.hive_db_data_migration
select 'update_posts_rshares( 0, head_block_number) execution'
where not exists (select null from hivemind_app.hive_db_patch_level where patched_to_revision = '431fdaead7dcd69e4d2a45e7ce8a3186b8075515')
;

-- updated to e8b65adf22654203f5a79937ff2a95c5c47e10c5 - See merge request hive/hivemind!251

-- COMMENTED OUT DUE TO MRs:processed below.
--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/298
--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/302
--CREATE INDEX IF NOT EXISTS hive_posts_is_paidout_idx ON hivemind_app.hive_posts (is_paidout);
--CREATE INDEX IF NOT EXISTS hive_posts_payout_plus_pending_payout_id ON hivemind_app.hive_posts ((payout+pending_payout), id);

INSERT INTO hivemind_app.hive_tag_data (id, tag) VALUES (0, '')
ON CONFLICT DO NOTHING;

--- updated to f2e5f656a421eb1dd71328a94a421934eda27a87 - See MR https://gitlab.syncad.com/hive/hivemind/-/merge_requests/275
DO
$BODY$
BEGIN
IF NOT EXISTS(SELECT data_type
              FROM information_schema.columns
              WHERE table_name = 'hive_follows' AND column_name = 'follow_muted') THEN
    RAISE NOTICE 'Performing hivemind_app.hive_follows upgrade - adding new column follow_muted';
    PERFORM hivemind_app.deps_save_and_drop_dependencies('public', 'hive_follows', true);
    alter table ONLY hivemind_app.hive_follows
      add column follow_muted boolean,
      alter column follow_muted set default False;

    --- Fill the default value for all existing records.
    update hivemind_app.hive_follows set follow_muted = False;

    alter table ONlY hivemind_app.hive_follows
      alter column follow_muted set not null;

    PERFORM hivemind_app.deps_restore_dependencies('public', 'hive_follows');
ELSE
  RAISE NOTICE 'hive_follows::follow_muted migration skipped';
END IF;

END
$BODY$;

--- 4cdf5d19f6cfcb73d3fa504cac9467c4df31c02e - https://gitlab.syncad.com/hive/hivemind/-/merge_requests/295
--- 9e126e9d762755f2b9a0fd68f076c9af6bb73b76 - https://gitlab.syncad.com/hive/hivemind/-/merge_requests/314 mentions fix
--- 1cc9981679157e4e54e5e4a74cca1feb5d49296d - fix for mentions notifications time value
INSERT INTO hivemind_app.hive_db_data_migration
select 'update_hive_post_mentions refill execution'
where not exists (select null from hivemind_app.hive_db_patch_level where patched_to_revision = '1cc9981679157e4e54e5e4a74cca1feb5d49296d' )
;

--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/298

DROP INDEX IF EXISTS hivemind_app.hive_posts_is_paidout_idx;
DROP INDEX IF EXISTS hivemind_app.hive_posts_sc_trend_id_idx;
DROP INDEX IF EXISTS hivemind_app.hive_posts_sc_hot_id_idx;

--- Commented out as it is dropped below.
--- CREATE INDEX IF NOT EXISTS hive_posts_sc_trend_id_is_paidout_idx ON hivemind_app.hive_posts(sc_trend, id, is_paidout );

--- Commented out as it is dropped below.
--- CREATE INDEX IF NOT EXISTS hive_posts_sc_hot_id_is_paidout_idx ON hivemind_app.hive_posts(sc_hot, id, is_paidout );

--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/302

DROP INDEX IF EXISTS hivemind_app.hive_posts_payout_plus_pending_payout_id;
--- Commented out as dropped below.
--- CREATE INDEX IF NOT EXISTS hive_posts_payout_plus_pending_payout_id_is_paidout_idx ON hivemind_app.hive_posts ((payout+pending_payout), id, is_paidout);

--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/310

CREATE INDEX IF NOT EXISTS hive_votes_voter_id_last_update_idx ON hivemind_app.hive_votes (voter_id, last_update);

--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/306 update posts children count fix
--- 0e3c8700659d98b45f1f7146dc46a195f905fc2d
INSERT INTO hivemind_app.hive_db_data_migration
select 'update_hive_posts_children_count execution'
where not exists (select null from hivemind_app.hive_db_patch_level where patched_to_revision = '0e3c8700659d98b45f1f7146dc46a195f905fc2d' )
;

-- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/372
INSERT INTO hivemind_app.hive_db_data_migration
select 'Notification cache initial fill'
where not exists (select null from hivemind_app.hive_db_patch_level where patched_to_revision = 'cc7bb174d40fe1a0e2221d5d7e1c332c344dca34' )
;

--- 1847c75702384c7e34c624fc91f24d2ef20df91d latest version of develop included in this migration script.

--- Rename hivemind_app.hive_votes_ux1 unique constraint to the hivemind_app.hive_votes_voter_id_author_id_permlink_id_uk
DO $$
BEGIN
IF EXISTS hivemind_app.(SELECT * FROM pg_constraint WHERE conname='hive_votes_ux1') THEN
  RAISE NOTICE 'Attempting to rename hivemind_app.hive_votes_ux1 to hivemind_app.hive_votes_voter_id_author_id_permlink_id_uk...';
  ALTER TABLE hivemind_app.hive_votes RENAME CONSTRAINT hivemind_app.hive_votes_ux1 to hivemind_app.hive_votes_voter_id_author_id_permlink_id_uk;
END IF;
END
$$
;

--- Change definition of index hivemind_app.hive_posts_created_at_author_id_idx to hivemind_app.hive_posts_author_id_created_at_idx to improve hivemind_app.hive_accounts_info_view performance.
DROP INDEX IF EXISTS hivemind_app.hive_posts_created_at_author_id_idx;

CREATE INDEX IF NOT EXISTS hive_posts_author_id_created_at_idx ON hivemind_app.hive_posts ( author_id DESC, created_at DESC);

CREATE INDEX IF NOT EXISTS hive_blocks_created_at_idx ON hivemind_app.hive_blocks (created_at);

-- Change done at https://gitlab.syncad.com/hive/hivemind/-/commit/c21f03b2d8cfa6af2386a222c7501580d1d1ce05
ALTER TABLE hivemind_app.hive_blocks ALTER COLUMN ops SET DATA TYPE INTEGER;

--- Notification cache to significantly speedup notification APIs.
CREATE TABLE IF NOT EXISTS hivemind_app.hive_notification_cache
(
  id BIGINT NOT NULL DEFAULT nextval('hive_notification_cache_id_seq'::regclass),
  block_num INT NOT NULL,
  type_id INT NOT NULL,
  dst INT NULL,
  src INT NULL,
  dst_post_id INT NULL,
  post_id INT NULL,
  score INT NOT NULL,
  created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL,
  community_title VARCHAR(32) NULL,
  community VARCHAR(16) NULL,
  payload VARCHAR NULL,

  CONSTRAINT hivemind_app.hive_notification_cache_pk PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS hive_notification_cache_block_num_idx ON hivemind_app.hive_notification_cache (block_num);
CREATE INDEX IF NOT EXISTS hive_notification_cache_dst_score_idx ON hivemind_app.hive_notification_cache (dst, score) WHERE dst IS NOT NULL;

CREATE INDEX IF NOT EXISTS hive_feed_cache_block_num_idx on hivemind_app.hive_feed_cache (block_num);
CREATE INDEX IF NOT EXISTS hive_feed_cache_created_at_idx on hivemind_app.hive_feed_cache (created_at);

--- condenser_get_trending_tags optimizations and slight index improvements.

DROP INDEX IF EXISTS hivemind_app.hive_posts_category_id_idx;

CREATE INDEX IF NOT EXISTS hive_posts_category_id_payout_plus_pending_payout_depth_idx ON hivemind_app.hive_posts (category_id, (payout + pending_payout), depth)
  WHERE NOT is_paidout AND counter_deleted = 0;

DROP INDEX IF EXISTS hivemind_app.hive_posts_sc_trend_id_is_paidout_idx;

CREATE INDEX IF NOT EXISTS hive_posts_sc_trend_id_idx ON hivemind_app.hive_posts USING btree (sc_trend, id)
  WHERE NOT is_paidout AND counter_deleted = 0 AND depth = 0
;

DROP INDEX IF EXISTS hivemind_app.hive_posts_sc_hot_id_is_paidout_idx;

CREATE INDEX IF NOT EXISTS hive_posts_sc_hot_id_idx ON hivemind_app.hive_posts (sc_hot, id)
  WHERE NOT is_paidout AND counter_deleted = 0 AND depth = 0
  ;

DROP INDEX IF EXISTS hivemind_app.hive_posts_payout_plus_pending_payout_id_is_paidout_idx;

CREATE INDEX IF NOT EXISTS hive_posts_payout_plus_pending_payout_id_idx ON hivemind_app.hive_posts ((payout + pending_payout), id)
  WHERE counter_deleted = 0 AND NOT is_paidout
;

DROP INDEX IF EXISTS hivemind_app.hive_posts_promoted_idx;

CREATE INDEX IF NOT EXISTS hive_posts_promoted_id_idx ON hivemind_app.hive_posts (promoted, id)
  WHERE NOT is_paidout AND counter_deleted = 0
 ;


 CREATE INDEX IF NOT EXISTS hive_posts_tags_ids_idx ON hivemind_app.hive_posts USING gin(tags_ids gin__int_ops);

 --DROP TABLE IF EXISTS hivemind_app.hive_post_tags;


CREATE SEQUENCE IF NOT EXISTS hivemind_app.hive_notification_cache_id_seq
    INCREMENT 1
    START 1
    MINVALUE 1
    MAXVALUE 9223372036854775807
    CACHE 1
    ;

ALTER TABLE hivemind_app.hive_notification_cache
  ALTER COLUMN id SET DEFAULT nextval('hive_notification_cache_id_seq'::regclass);

 -- Changes done in https://gitlab.syncad.com/hive/hivemind/-/merge_requests/452
 DROP INDEX IF EXISTS hivemind_app.hive_posts_parent_id_idx;

 CREATE INDEX IF NOT EXISTS hive_posts_parent_id_counter_deleted_id_idx ON hivemind_app.hive_posts (parent_id, counter_deleted, id);

 DROP INDEX IF EXISTS hivemind_app.hive_posts_author_id_created_at_idx;

 CREATE INDEX IF NOT EXISTS hive_posts_author_id_created_at_id_idx ON hivemind_app.hive_posts (author_id DESC, created_at DESC, id);

 DROP INDEX IF EXISTS hivemind_app.hive_posts_author_posts_idx;

 CREATE INDEX IF NOT EXISTS hive_posts_author_id_id_idx ON hivemind_app.hive_posts (author_id, id)
 WHERE depth = 0;

 CREATE INDEX IF NOT EXISTS hive_feed_cache_post_id_idx ON hivemind_app.hive_feed_cache (post_id);

-- Changes made in https://gitlab.syncad.com/hive/hivemind/-/merge_requests/454
DROP INDEX IF EXISTS hivemind_app.hive_posts_parent_id_counter_deleted_id_idx;

CREATE INDEX IF NOT EXISTS hive_posts_parent_id_id_idx ON hivemind_app.hive_posts (parent_id, id DESC) where counter_deleted = 0;

--- Drop this view as it was eliminated.
DROP VIEW IF EXISTS hivemind_app.hive_posts_view CASCADE;

DO
$$
BEGIN
--- Changes done at commit https://gitlab.syncad.com/hive/hivemind/-/commit/d243747e7ff37a6f0bdef88ce5fc3c471b39b238
IF NOT EXISTS (SELECT NULL FROM hivemind_app.hive_db_patch_level where patched_to_revision = 'd243747e7ff37a6f0bdef88ce5fc3c471b39b238') THEN
  DROP INDEX IF EXISTS hivemind_app.hive_posts_payout_plus_pending_payout_id_idx;
  CREATE INDEX hive_posts_payout_plus_pending_payout_id_idx
    ON hivemind_app.hive_posts USING btree
    ((payout + pending_payout) ASC NULLS LAST, id ASC NULLS LAST)
    WHERE NOT is_paidout AND counter_deleted = 0;
END IF;
END
$$;

DO
$$
BEGIN
IF NOT EXISTS(SELECT data_type
              FROM information_schema.columns
              WHERE table_name = 'hive_blocks' AND column_name = 'completed') THEN
    RAISE NOTICE 'Performing hivemind_app.hive_blocks upgrade - adding new column: `completed`';
    PERFORM hivemind_app.deps_save_and_drop_dependencies('public', 'hive_blocks', true);
    ALTER TABLE ONLY hivemind_app.hive_blocks
      ADD COLUMN completed BOOLEAN,
      ALTER COLUMN completed SET DEFAULT False;

    UPDATE hivemind_app.hive_blocks SET completed = True;

    ALTER TABLE ONlY hivemind_app.hive_blocks
      ALTER COLUMN completed SET NOT NULL;

    PERFORM hivemind_app.deps_restore_dependencies('public', 'hive_blocks');

    CREATE INDEX hive_blocks_completed_idx ON hivemind_app.hive_blocks USING btree
      (completed ASC NULLS LAST);
ELSE
  RAISE NOTICE 'hive_blocks::completed migration skipped';
END IF;
END
$$
;

--- Changes done in https://gitlab.syncad.com/hive/hivemind/-/commit/02c3c807c1a65635b98b6657196c10af44ec9d92

CREATE INDEX IF NOT EXISTS hivemind_app.hive_votes_post_id_block_num_rshares_vote_is_effective_idx
  ON hivemind_app.hive_votes USING btree
  (post_id ASC NULLS LAST, block_num ASC NULLS LAST, rshares ASC NULLS LAST, is_effective ASC NULLS LAST)
;

DROP INDEX IF EXISTS hivemind_app.hive_accounts_ix6;

--- previously there was a typo and redunant index could be created after fresh instance (where in the python code hive_accounts_reputation_id_idx was created) has applied upgrade.
DROP INDEX IF EXISTS hivemind_app.hive_accounts_reputation_id;

CREATE INDEX IF NOT EXISTS hivemind_app.hive_accounts_reputation_id_idx
  ON hivemind_app.hive_accounts USING btree
  (reputation desc, id asc)
  ;
