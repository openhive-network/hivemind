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

DO
$BODY$
BEGIN
IF NOT EXISTS(SELECT data_type
              FROM information_schema.columns
              WHERE table_name = 'hive_accounts' AND column_name = 'is_implicit') THEN
    RAISE NOTICE 'Performing hive_accounts upgrade - adding new column is_implicit';
    PERFORM deps_save_and_drop_dependencies('public', 'hive_accounts', true);
    alter table ONlY hive_accounts
      add column is_implicit boolean,
      alter column is_implicit set default True;

    --- reputations have to be recalculated from scratch.
    update hive_accounts set reputation = 0, is_implicit = True;

    alter table ONlY hive_accounts
      alter column is_implicit set not null;

    perform deps_restore_dependencies('public', 'hive_accounts');

    INSERT INTO hive_db_data_migration VALUES ('Reputation calculation');
ELSE
  RAISE NOTICE 'hive_accounts::is_implicit migration skipped';
END IF;

IF EXISTS(SELECT data_type
          FROM information_schema.columns
          WHERE table_name = 'hive_accounts' AND column_name = 'blacklist_description') THEN
    RAISE NOTICE 'Performing hive_accounts upgrade - removing columns blacklist_description/muted_list_description';
    -- drop hive_accounts_info_view since it uses removed column. It will be rebuilt after upgrade
    DROP VIEW IF EXISTS hive_accounts_info_view;

    PERFORM deps_save_and_drop_dependencies('public', 'hive_accounts', true);
    ALTER TABLE ONlY hive_accounts
      DROP COLUMN IF EXISTS blacklist_description,
      DROP COLUMN IF EXISTS muted_list_description
      ;
ELSE
  RAISE NOTICE 'hive_accounts::blacklist_description/muted_list_description migration skipped';
END IF;

END
$BODY$;

DROP TABLE IF EXISTS hive_account_reputation_status;

drop index if exists hive_posts_sc_hot_idx;
drop index if exists hive_posts_sc_trend_idx;
drop index if exists hive_reblogs_blogger_id;
drop index if exists hive_subscriptions_community_idx;
drop index if exists hive_votes_post_id_idx;
drop index if exists hive_votes_voter_id_idx;
drop index if exists hive_votes_last_update_idx;
drop index if exists hive_posts_community_id_idx;

CREATE INDEX IF NOT EXISTS hive_posts_cashout_time_id_idx ON hive_posts (cashout_time, id);
CREATE INDEX IF NOT EXISTS hive_posts_updated_at_idx ON hive_posts (updated_at DESC);
CREATE INDEX IF NOT EXISTS hive_votes_block_num_idx ON hive_votes (block_num);
CREATE INDEX IF NOT EXISTS hive_posts_community_id_id_idx ON hive_posts (community_id, id DESC);

DO
$BODY$
BEGIN
IF NOT EXISTS(SELECT data_type
              FROM information_schema.columns
              WHERE table_name = 'hive_posts_api_helper' AND column_name = 'author_s_permlink') THEN
    RAISE NOTICE 'Performing hive_posts_api_helper upgrade - adding new column author_s_permlink';
    PERFORM deps_save_and_drop_dependencies('public', 'hive_posts_api_helper', true);

    DROP INDEX IF EXISTS hive_posts_api_helper_parent_permlink_or_category;
    DROP TABLE IF EXISTS hive_posts_api_helper;

    CREATE TABLE public.hive_posts_api_helper
    (
        id integer NOT NULL,
        author_s_permlink character varying(275) COLLATE pg_catalog."C" NOT NULL,
        CONSTRAINT hive_posts_api_helper_pkey PRIMARY KEY (id)
    );

    perform deps_restore_dependencies('public', 'hive_posts_api_helper');

    CREATE INDEX IF NOT EXISTS hive_posts_api_helper_author_s_permlink_idx ON hive_posts_api_helper (author_s_permlink);

    INSERT INTO hive_db_data_migration VALUES ('hive_posts_api_helper fill');
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
  RAISE NOTICE 'Performing hive_mentions upgrade - adding new column block_num';

  TRUNCATE TABLE public.hive_mentions RESTART IDENTITY;
  PERFORM deps_save_and_drop_dependencies('public', 'hive_mentions', true);

  ALTER TABLE hive_mentions
    DROP CONSTRAINT IF EXISTS hive_mentions_pk,
    ADD COLUMN IF NOT EXISTS id SERIAL,
    ADD COLUMN  IF NOT EXISTS block_num INTEGER,
    ALTER COLUMN id SET NOT NULL,
    ALTER COLUMN block_num SET NOT NULL,
    ADD CONSTRAINT hive_mentions_pk PRIMARY KEY (id);

  perform deps_restore_dependencies('public', 'hive_mentions');

  INSERT INTO hive_db_data_migration VALUES ('hive_mentions fill');
ELSE
  ALTER TABLE public.hive_mentions
    DROP CONSTRAINT hive_mentions_ux1;
  ALTER TABLE public.hive_mentions
    ADD CONSTRAINT hive_mentions_ux1 UNIQUE (post_id, account_id, block_num);
END IF;
END
$BODY$
;

---------------------------------------------------------------------------------------------------
--                                hive_posts table migration
---------------------------------------------------------------------------------------------------

DO
$BODY$
BEGIN
IF EXISTS(SELECT data_type
              FROM information_schema.columns
              WHERE table_name = 'hive_posts' AND column_name = 'is_grayed') THEN
  RAISE NOTICE 'Performing hive_posts upgrade - dropping is_grayed column';

  --- Warning we need to first drop hive_posts view since it references column is_grayed, which will be dropped.
  --- Saving it in the dependencies, will restore wrong (old) definition of the view and make an error.
  DROP VIEW IF EXISTS hive_posts_view CASCADE;

  PERFORM deps_save_and_drop_dependencies('public', 'hive_posts', true);

  ALTER TABLE hive_posts
    DROP COLUMN IF EXISTS is_grayed;

  perform deps_restore_dependencies('public', 'hive_posts');
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
  RAISE NOTICE 'Performing hive_posts upgrade - adding block_num_created column, type change for abs_rshares/vote_rshares columns';

  PERFORM deps_save_and_drop_dependencies('public', 'hive_posts', true);

  ALTER TABLE ONLY hive_posts
    ALTER COLUMN abs_rshares SET DATA TYPE NUMERIC,
    ALTER COLUMN vote_rshares SET DATA TYPE NUMERIC,
    ADD COLUMN block_num_created INTEGER;

    UPDATE hive_posts SET block_num_created = 1; -- Artificial number, since we don't have this info atm, it requires full sync

    ALTER TABLE ONLY hive_posts
      ALTER COLUMN block_num_created set not null;

  perform deps_restore_dependencies('public', 'hive_posts');
ELSE
  RAISE NOTICE 'SKIPPING hive_posts upgrade - adding a block_num_created column, type change for abs_rshares/vote_rshares columns';
END IF;

--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/367
IF NOT EXISTS (SELECT data_type FROM information_schema.columns
               WHERE table_name = 'hive_posts' AND column_name = 'total_votes')
   AND NOT EXISTS (SELECT data_type FROM information_schema.columns
                 WHERE table_name = 'hive_posts' AND column_name = 'net_votes') THEN
  RAISE NOTICE 'Performing hive_posts upgrade - adding total_votes and net_votes columns';

  PERFORM deps_save_and_drop_dependencies('public', 'hive_posts', true);

  ALTER TABLE ONLY hive_posts
    ADD COLUMN total_votes BIGINT,
    ADD COLUMN net_votes BIGINT;

  UPDATE hive_posts SET total_votes = 0, net_votes = 0; -- Artificial number, requires to start update_posts_rshares for all blocks

  ALTER TABLE ONLY hive_posts
    ALTER COLUMN total_votes SET NOT NULL,
    ALTER COLUMN total_votes SET DEFAULT 0,
    ALTER COLUMN net_votes SET NOT NULL,
    ALTER COLUMN net_votes SET DEFAULT 0;

  PERFORM deps_restore_dependencies('public', 'hive_posts');
ELSE
  RAISE NOTICE 'SKIPPING hive_posts upgrade - adding total_votes and net_votes columns';
END IF;

IF NOT EXISTS(SELECT data_type FROM information_schema.columns
          WHERE table_name = 'hive_posts' AND column_name = 'tags_ids') THEN
    ALTER TABLE ONLY hive_posts
            ADD COLUMN tags_ids INTEGER[];

    UPDATE hive_posts hp
    SET
        tags_ids = tags.tags
    FROM
    (
      SELECT
          post_id as post_id,
          array_agg( hpt.tag_id ) as tags
      FROM
        hive_post_tags hpt
      GROUP BY post_id
    ) as tags
    WHERE hp.id = tags.post_id;
ELSE
    RAISE NOTICE 'SKIPPING hive_posts upgrade - adding a tags_ids column';
END IF;

END

$BODY$
;

DROP INDEX IF EXISTS hive_posts_created_at_idx;
-- skip it since it is dropped below.
-- CREATE INDEX IF NOT EXISTS hive_posts_created_at_author_id_idx ON hive_posts (created_at, author_id);

CREATE INDEX IF NOT EXISTS hive_posts_block_num_created_idx ON hive_posts (block_num_created);

DROP INDEX IF EXISTS hive_mentions_post_id_idx;

-- updated up to 7b8def051be224a5ebc360465f7a1522090c7125
-- updated up to 033619277eccea70118a5b8dc0c73b913da0025f
INSERT INTO hive_db_data_migration
select 'update_posts_rshares( 0, head_block_number) execution'
where not exists (select null from hive_db_patch_level where patched_to_revision = '431fdaead7dcd69e4d2a45e7ce8a3186b8075515')
;

-- updated to e8b65adf22654203f5a79937ff2a95c5c47e10c5 - See merge request hive/hivemind!251

-- COMMENTED OUT DUE TO MRs:processed below.
--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/298
--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/302
--CREATE INDEX IF NOT EXISTS hive_posts_is_paidout_idx ON hive_posts (is_paidout);
--CREATE INDEX IF NOT EXISTS hive_posts_payout_plus_pending_payout_id ON hive_posts ((payout+pending_payout), id);

INSERT INTO hive_tag_data (id, tag) VALUES (0, '')
ON CONFLICT DO NOTHING;

--- updated to f2e5f656a421eb1dd71328a94a421934eda27a87 - See MR https://gitlab.syncad.com/hive/hivemind/-/merge_requests/275
DO
$BODY$
BEGIN
IF NOT EXISTS(SELECT data_type
              FROM information_schema.columns
              WHERE table_name = 'hive_follows' AND column_name = 'follow_muted') THEN
    RAISE NOTICE 'Performing hive_follows upgrade - adding new column follow_muted';
    PERFORM deps_save_and_drop_dependencies('public', 'hive_follows', true);
    alter table ONLY hive_follows
      add column follow_muted boolean,
      alter column follow_muted set default False;

    --- Fill the default value for all existing records.
    update hive_follows set follow_muted = False;

    alter table ONlY hive_follows
      alter column follow_muted set not null;

    perform deps_restore_dependencies('public', 'hive_follows');
ELSE
  RAISE NOTICE 'hive_follows::follow_muted migration skipped';
END IF;

END
$BODY$;

--- 4cdf5d19f6cfcb73d3fa504cac9467c4df31c02e - https://gitlab.syncad.com/hive/hivemind/-/merge_requests/295
--- 9e126e9d762755f2b9a0fd68f076c9af6bb73b76 - https://gitlab.syncad.com/hive/hivemind/-/merge_requests/314 mentions fix
--- 1cc9981679157e4e54e5e4a74cca1feb5d49296d - fix for mentions notifications time value
INSERT INTO hive_db_data_migration
select 'update_hive_post_mentions refill execution'
where not exists (select null from hive_db_patch_level where patched_to_revision = '1cc9981679157e4e54e5e4a74cca1feb5d49296d' )
;

--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/298

DROP INDEX IF EXISTS hive_posts_is_paidout_idx;
DROP INDEX IF EXISTS hive_posts_sc_trend_id_idx;
DROP INDEX IF EXISTS hive_posts_sc_hot_id_idx;

--- Commented out as it is dropped below.
--- CREATE INDEX IF NOT EXISTS hive_posts_sc_trend_id_is_paidout_idx ON hive_posts(sc_trend, id, is_paidout );

--- Commented out as it is dropped below.
--- CREATE INDEX IF NOT EXISTS hive_posts_sc_hot_id_is_paidout_idx ON hive_posts(sc_hot, id, is_paidout );

--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/302

DROP INDEX IF EXISTS hive_posts_payout_plus_pending_payout_id;
--- Commented out as dropped below.
--- CREATE INDEX IF NOT EXISTS hive_posts_payout_plus_pending_payout_id_is_paidout_idx ON hive_posts ((payout+pending_payout), id, is_paidout);

--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/310

CREATE INDEX IF NOT EXISTS hive_votes_voter_id_last_update_idx ON hive_votes (voter_id, last_update);

--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/306 update posts children count fix
--- 0e3c8700659d98b45f1f7146dc46a195f905fc2d
INSERT INTO hive_db_data_migration
select 'update_hive_posts_children_count execution'
where not exists (select null from hive_db_patch_level where patched_to_revision = '0e3c8700659d98b45f1f7146dc46a195f905fc2d' )
;

-- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/372
INSERT INTO hive_db_data_migration
select 'Notification cache initial fill'
where not exists (select null from hive_db_patch_level where patched_to_revision = 'cc7bb174d40fe1a0e2221d5d7e1c332c344dca34' )
;

--- 1847c75702384c7e34c624fc91f24d2ef20df91d latest version of develop included in this migration script.

--- Rename hive_votes_ux1 unique constraint to the hive_votes_voter_id_author_id_permlink_id_uk
DO $$
BEGIN
IF EXISTS (SELECT * FROM pg_constraint WHERE conname='hive_votes_ux1') THEN
  RAISE NOTICE 'Attempting to rename hive_votes_ux1 to hive_votes_voter_id_author_id_permlink_id_uk...';
  ALTER TABLE hive_votes RENAME CONSTRAINT hive_votes_ux1 to hive_votes_voter_id_author_id_permlink_id_uk;
END IF;
END
$$
;

--- Change definition of index hive_posts_created_at_author_id_idx to hive_posts_author_id_created_at_idx to improve hive_accounts_info_view performance.
DROP INDEX IF EXISTS public.hive_posts_created_at_author_id_idx;

CREATE INDEX IF NOT EXISTS hive_posts_author_id_created_at_idx ON public.hive_posts ( author_id DESC, created_at DESC);

CREATE INDEX IF NOT EXISTS hive_blocks_created_at_idx ON hive_blocks (created_at);

-- Change done at https://gitlab.syncad.com/hive/hivemind/-/commit/c21f03b2d8cfa6af2386a222c7501580d1d1ce05
ALTER TABLE hive_blocks ALTER COLUMN ops SET DATA TYPE INTEGER;

--- Notification cache to significantly speedup notification APIs.
CREATE TABLE IF NOT EXISTS hive_notification_cache
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

  CONSTRAINT hive_notification_cache_pk PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS hive_notification_cache_block_num_idx ON hive_notification_cache (block_num);
CREATE INDEX IF NOT EXISTS hive_notification_cache_dst_score_idx ON hive_notification_cache (dst, score) WHERE dst IS NOT NULL;

CREATE INDEX IF NOT EXISTS hive_feed_cache_block_num_idx on hive_feed_cache (block_num);
CREATE INDEX IF NOT EXISTS hive_feed_cache_created_at_idx on hive_feed_cache (created_at);

--- condenser_get_trending_tags optimizations and slight index improvements.

DROP INDEX IF EXISTS hive_posts_category_id_idx;

CREATE INDEX IF NOT EXISTS hive_posts_category_id_payout_plus_pending_payout_depth_idx ON hive_posts (category_id, (payout + pending_payout), depth)
  WHERE NOT is_paidout AND counter_deleted = 0;

DROP INDEX IF EXISTS hive_posts_sc_trend_id_is_paidout_idx;

CREATE INDEX IF NOT EXISTS hive_posts_sc_trend_id_idx ON hive_posts USING btree (sc_trend, id)
  WHERE NOT is_paidout AND counter_deleted = 0 AND depth = 0
;

DROP INDEX IF EXISTS hive_posts_sc_hot_id_is_paidout_idx;

CREATE INDEX IF NOT EXISTS hive_posts_sc_hot_id_idx ON hive_posts (sc_hot, id)
  WHERE NOT is_paidout AND counter_deleted = 0 AND depth = 0
  ;

DROP INDEX IF EXISTS hive_posts_payout_plus_pending_payout_id_is_paidout_idx;

CREATE INDEX IF NOT EXISTS hive_posts_payout_plus_pending_payout_id_idx ON hive_posts ((payout + pending_payout), id)
  WHERE counter_deleted = 0 AND NOT is_paidout
;

DROP INDEX IF EXISTS hive_posts_promoted_idx;

CREATE INDEX IF NOT EXISTS hive_posts_promoted_id_idx ON hive_posts (promoted, id)
  WHERE NOT is_paidout AND counter_deleted = 0
 ;


 CREATE INDEX IF NOT EXISTS hive_posts_tags_ids_idx ON hive_posts USING gin(tags_ids gin__int_ops);

 --DROP TABLE IF EXISTS hive_post_tags;


CREATE SEQUENCE IF NOT EXISTS hive_notification_cache_id_seq
    INCREMENT 1
    START 1
    MINVALUE 1
    MAXVALUE 9223372036854775807
    CACHE 1
    ;

ALTER TABLE hive_notification_cache
  ALTER COLUMN id SET DEFAULT nextval('hive_notification_cache_id_seq'::regclass);

 -- Changes done in https://gitlab.syncad.com/hive/hivemind/-/merge_requests/452
 DROP INDEX IF EXISTS hive_posts_parent_id_idx;

 CREATE INDEX IF NOT EXISTS hive_posts_parent_id_counter_deleted_id_idx ON hive_posts (parent_id, counter_deleted, id);

 DROP INDEX IF EXISTS hive_posts_author_id_created_at_idx;

 CREATE INDEX IF NOT EXISTS hive_posts_author_id_created_at_id_idx ON hive_posts (author_id DESC, created_at DESC, id);

 DROP INDEX IF EXISTS hive_posts_author_posts_idx;

 CREATE INDEX IF NOT EXISTS hive_posts_author_id_id_idx ON hive_posts (author_id, id)
 WHERE depth = 0;

 CREATE INDEX IF NOT EXISTS hive_feed_cache_post_id_idx ON hive_feed_cache (post_id);

-- Changes made in https://gitlab.syncad.com/hive/hivemind/-/merge_requests/454
DROP INDEX IF EXISTS hive_posts_parent_id_counter_deleted_id_idx;

CREATE INDEX IF NOT EXISTS hive_posts_parent_id_id_idx ON hive_posts (parent_id, id DESC) where counter_deleted = 0;

--- Drop this view as it was eliminated.
DROP VIEW IF EXISTS hive_posts_view CASCADE;

DO
$$
BEGIN
--- Changes done at commit https://gitlab.syncad.com/hive/hivemind/-/commit/d243747e7ff37a6f0bdef88ce5fc3c471b39b238
IF NOT EXISTS (SELECT NULL FROM hive_db_patch_level where patched_to_revision = 'd243747e7ff37a6f0bdef88ce5fc3c471b39b238') THEN
  DROP INDEX IF EXISTS hive_posts_payout_plus_pending_payout_id_idx;
  CREATE INDEX hive_posts_payout_plus_pending_payout_id_idx
    ON hive_posts USING btree
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
    RAISE NOTICE 'Performing hive_blocks upgrade - adding new column: `completed`';
    PERFORM deps_save_and_drop_dependencies('public', 'hive_blocks', true);
    ALTER TABLE ONLY hive_blocks
      ADD COLUMN completed BOOLEAN,
      ALTER COLUMN completed SET DEFAULT False;

    UPDATE hive_blocks SET completed = True;

    ALTER TABLE ONlY hive_blocks
      ALTER COLUMN completed SET NOT NULL;

    perform deps_restore_dependencies('public', 'hive_blocks');

    CREATE INDEX hive_blocks_completed_idx ON hive_blocks USING btree
      (completed ASC NULLS LAST);
ELSE
  RAISE NOTICE 'hive_blocks::completed migration skipped';
END IF;
END
$$
;

--- Changes done in https://gitlab.syncad.com/hive/hivemind/-/commit/02c3c807c1a65635b98b6657196c10af44ec9d92

CREATE INDEX IF NOT EXISTS hive_votes_post_id_block_num_rshares_vote_is_effective_idx
  ON hive_votes USING btree
  (post_id ASC NULLS LAST, block_num ASC NULLS LAST, rshares ASC NULLS LAST, is_effective ASC NULLS LAST)
;

DROP INDEX IF EXISTS hive_accounts_ix6;

--- previously there was a typo and redunant index could be created after fresh instance (where in the python code hive_accounts_reputation_id_idx was created) has applied upgrade.
DROP INDEX IF EXISTS hive_accounts_reputation_id;

CREATE INDEX IF NOT EXISTS hive_accounts_reputation_id_idx
  ON public.hive_accounts USING btree
  (reputation desc, id asc)
  ;

--- Begin changes done in MR https://gitlab.syncad.com/hive/hivemind/-/merge_requests/574

DROP INDEX IF EXISTS hivemind_app.hive_posts_community_id_id_idx;

CREATE INDEX IF NOT EXISTS hive_posts_community_id_id_idx
    ON public.hive_posts USING btree
    (community_id ASC NULLS LAST)
    INCLUDE(id)
    WHERE counter_deleted = 0;

DROP INDEX IF EXISTS hive_posts_community_id_is_pinned_idx;

CREATE INDEX IF NOT EXISTS hive_posts_community_id_is_pinned_idx
    ON public.hive_posts USING btree
    (community_id ASC NULLS LAST)
    INCLUDE(id)
    WHERE is_pinned AND counter_deleted = 0;

--- End of MR https://gitlab.syncad.com/hive/hivemind/-/merge_requests/574
