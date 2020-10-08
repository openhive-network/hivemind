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

DO $$
BEGIN
  EXECUTE 'ALTER DATABASE '||current_database()||' SET join_collapse_limit TO 16';
  EXECUTE 'ALTER DATABASE '||current_database()||' SET from_collapse_limit TO 16';
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

CREATE INDEX IF NOT EXISTS hive_posts_cashout_time_id_idx ON hive_posts (cashout_time, id);
CREATE INDEX IF NOT EXISTS hive_posts_updated_at_idx ON hive_posts (updated_at DESC);
CREATE INDEX IF NOT EXISTS hive_votes_block_num_idx ON hive_votes (block_num);

DO
$BODY$
BEGIN
IF NOT EXISTS(SELECT data_type
              FROM information_schema.columns
              WHERE table_name = 'hive_posts_api_helper' AND column_name = 'permlink') THEN
    RAISE NOTICE 'Performing hive_posts_api_helper upgrade - adding new column permlink';
    PERFORM deps_save_and_drop_dependencies('public', 'hive_posts_api_helper', true);

    DROP INDEX IF EXISTS hive_posts_api_helper_parent_permlink_or_category;
    DROP TABLE IF EXISTS hive_posts_api_helper;

    CREATE TABLE public.hive_posts_api_helper
    (
        id integer NOT NULL,
        author character varying(16) COLLATE pg_catalog."C" NOT NULL,
        permlink character varying(255) COLLATE pg_catalog."C" NOT NULL,
        CONSTRAINT hive_posts_api_helper_pkey PRIMARY KEY (id)
    );

    perform deps_restore_dependencies('public', 'hive_posts_api_helper');

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

  TRUNCATE TABLE public.hive_mentions;
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
END IF;
END
$BODY$
;

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

  INSERT INTO hive_db_data_migration VALUES ('hive_mentions fill');
END IF;
END
$BODY$
;

DROP INDEX IF EXISTS hive_mentions_post_id_idx;

-- updated up to 7b8def051be224a5ebc360465f7a1522090c7125

INSERT INTO hive_db_data_migration 
select 'update_hot_and_trending_for_blocks( 0, head_block_number) execution'
where not exists (select null from hive_db_patch_level where patched_to_revision = '0be8e6e8b2121a8f768113e35e47725856c5da7c' )
;

-- updated to e8b65adf22654203f5a79937ff2a95c5c47e10c5 - See merge request hive/hivemind!251

CREATE INDEX IF NOT EXISTS hive_posts_is_paidout_idx ON hive_posts (is_paidout);
CREATE INDEX IF NOT EXISTS hive_posts_payout_plus_pending_payout_id ON hive_posts ((payout+pending_payout), id);

INSERT INTO hive_tag_data (id, tag) VALUES (0, '')
ON CONFLICT DO NOTHING;
