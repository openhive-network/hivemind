do $$
BEGIN
  ASSERT (SELECT setting FROM pg_settings where name='join_collapse_limit' and source='database')::int = 16, 'Bad optimizer settings, use install_app.sh script to setup target database correctly';
  ASSERT (SELECT setting FROM pg_settings where name='from_collapse_limit' and source='database')::int = 16, 'Bad optimizer settings, use install_app.sh script to setup target database correctly';
  ASSERT (SELECT setting FROM pg_settings where name='jit' and source='database')::BOOLEAN = False, 'Bad optimizer settings, use install_app.sh script to setup target database correctly';
END$$;

-- In case such tables have been created directly by admin, drop them first to allow correct creation and access during upgrade process.
DROP TABLE IF EXISTS hivemind_app.hive_db_vacuum_needed;
DROP TABLE IF EXISTS hivemind_app.hive_db_data_migration;
DROP TABLE IF EXISTS hivemind_app.hive_posts_api_helper;

SET ROLE hivemind;

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

-- condenser_api.get_followers pages on (following, follower_name). Account names never change, so the copy
-- filled here never goes stale. follows is rebuilt rather than UPDATEd: an UPDATE writes a second version of every
-- row, which leaves the table and its indexes doubled. Tables upgraded that way are rebuilt too, recognised by a heap
-- of over 80 bytes per row (a rebuilt one takes 54).
-- The rows are copied under a SHARE lock, which blocks only writes. Readers wait only from the TRUNCATE to the end
-- of this script: the refill and the index builds, about a minute for mainnet's 103 M rows. TRUNCATE, unlike a
-- swapped-in table, keeps the OID other applications' views of follows (hafsql.follows) depend on. The copy keeps
-- the heap's order: a serial scan, hash-joined in memory, with synchronized seq scans off.
-- This block comes first, so the locks this script's later statements take are not held through the copy.
-- follows_following_idx is not rebuilt: follows_following_follower_name_idx, created after it, replaces it.
-- The rebuilt pages are not all-visible until vacuumed: the sync's visibility watch vacuums follows when it starts.
DO $$
DECLARE
  _has_name BOOLEAN := EXISTS (SELECT NULL FROM pg_attribute WHERE attrelid = 'hivemind_app.follows'::regclass AND attname = 'follower_name' AND NOT attisdropped);
  _create TEXT[];
  _drop TEXT[];
  _ddl TEXT;
BEGIN
  IF _has_name AND (SELECT c.reltuples <= 0 OR pg_relation_size(c.oid) < 1024^3 OR pg_relation_size(c.oid) <= 80 * c.reltuples
                    FROM pg_class c WHERE c.oid = 'hivemind_app.follows'::regclass) THEN
    RETURN;
  END IF;
  LOCK TABLE hivemind_app.follows IN SHARE MODE;
  -- With no rows there is nothing to copy. This also keeps a shape's empty, full-size files and its statistics.
  IF NOT EXISTS (SELECT NULL FROM hivemind_app.follows) THEN
    DROP INDEX IF EXISTS hivemind_app.follows_following_idx;
    ALTER TABLE hivemind_app.follows ADD COLUMN IF NOT EXISTS follower_name VARCHAR(16) COLLATE "C" NOT NULL;
    RETURN;
  END IF;
  RAISE NOTICE 'Rebuilding hivemind_app.follows with follower_name';
  PERFORM set_config('max_parallel_workers_per_gather', '0', true);
  PERFORM set_config('work_mem', '1GB', true);
  PERFORM set_config('synchronize_seqscans', 'off', true);
  CREATE TEMP TABLE follows_rebuild ON COMMIT DROP AS
  SELECT f.follower, f.following, f.block_num, ha.name AS follower_name
  FROM hivemind_app.follows f LEFT JOIN hivemind_app.hive_accounts ha ON ha.id = f.follower;

  -- Recreated after the refill as they are now, except follows_following_idx.
  SELECT array_agg(format('ALTER TABLE hivemind_app.follows ADD CONSTRAINT %I %s', conname, pg_get_constraintdef(oid))),
         array_agg(format('ALTER TABLE hivemind_app.follows DROP CONSTRAINT %I', conname))
  INTO _create, _drop
  FROM pg_constraint WHERE conrelid = 'hivemind_app.follows'::regclass AND contype IN ('p', 'u', 'x');
  SELECT coalesce(_create, '{}') || coalesce(array_agg(pg_get_indexdef(i.indexrelid)) FILTER (WHERE i.indexrelid IS DISTINCT FROM to_regclass('hivemind_app.follows_following_idx')), '{}'),
         coalesce(_drop, '{}') || coalesce(array_agg(format('DROP INDEX %s', i.indexrelid::regclass)), '{}')
  INTO _create, _drop
  FROM pg_index i
  WHERE i.indrelid = 'hivemind_app.follows'::regclass AND NOT EXISTS (SELECT NULL FROM pg_constraint c WHERE c.conindid = i.indexrelid);

  FOREACH _ddl IN ARRAY _drop LOOP
    EXECUTE _ddl;
  END LOOP;
  TRUNCATE hivemind_app.follows;
  ALTER TABLE hivemind_app.follows ADD COLUMN IF NOT EXISTS follower_name VARCHAR(16) COLLATE "C" NOT NULL;
  INSERT INTO hivemind_app.follows (follower, following, block_num, follower_name)
  SELECT follower, following, block_num, follower_name FROM follows_rebuild;
  FOREACH _ddl IN ARRAY _create LOOP
    EXECUTE _ddl;
  END LOOP;
  ANALYZE hivemind_app.follows;
END
$$;
CREATE INDEX IF NOT EXISTS follows_following_follower_name_idx ON hivemind_app.follows (following, follower_name);
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS follows_following_follower_name_idx ON hivemind_app.follows (following, follower_name)');

-- hive_accounts.post_count, the account's hive_posts rows with counter_deleted = 0, which block processing keeps from
-- here on. The counts are taken first, under a SHARE lock on hive_posts that blocks only writes, so readers of
-- hive_accounts wait only for the fill, from the ALTER TABLE to the end of this script. The column is filled by the
-- rewrite a type change makes, not by an UPDATE: that would write a second version of the row of every account with
-- posts, leaving the table and its indexes up to doubled. The rewritten pages are not all-visible until vacuumed.
DO $$
BEGIN
  IF EXISTS (SELECT NULL FROM pg_attribute WHERE attrelid = 'hivemind_app.hive_accounts'::regclass AND attname = 'post_count' AND NOT attisdropped) THEN
    RETURN;
  END IF;
  -- With no rows there is nothing to fill. This also keeps a shape's empty, full-size files and its statistics.
  IF NOT EXISTS (SELECT NULL FROM hivemind_app.hive_accounts) THEN
    ALTER TABLE hivemind_app.hive_accounts ADD COLUMN post_count INTEGER NOT NULL DEFAULT 0;
    RETURN;
  END IF;
  RAISE NOTICE 'Adding hivemind_app.hive_accounts.post_count';
  LOCK TABLE hivemind_app.hive_posts IN SHARE MODE;
  PERFORM set_config('work_mem', '1GB', true);
  CREATE TEMP TABLE account_post_counts ON COMMIT DROP AS
  SELECT hp.author_id, COUNT(*)::INTEGER AS post_count
  FROM hivemind_app.hive_posts hp
  WHERE hp.counter_deleted = 0
  GROUP BY hp.author_id;
  ALTER TABLE account_post_counts ADD PRIMARY KEY (author_id);
  CREATE FUNCTION pg_temp.account_post_count(_account_id INTEGER) RETURNS INTEGER LANGUAGE sql STABLE
  AS 'SELECT COALESCE((SELECT apc.post_count FROM account_post_counts apc WHERE apc.author_id = _account_id), 0)';

  ALTER TABLE hivemind_app.hive_accounts ADD COLUMN post_count BIGINT NOT NULL DEFAULT 0;
  ALTER TABLE hivemind_app.hive_accounts ALTER COLUMN post_count TYPE INTEGER USING pg_temp.account_post_count(id);
  ANALYZE hivemind_app.hive_accounts;
END
$$;

DROP INDEX IF EXISTS hive_posts_tags_ids_idx;
DROP INDEX IF EXISTS hive_posts_tags_ids_live_post_cond_idx;
DROP INDEX IF EXISTS hive_posts_tags_ids_live_cond_idx;

CREATE TABLE IF NOT EXISTS hivemind_app.hive_post_tags (
    --- Column must be explicitly declared to satisfy further ALTER TABLE needed to INHERIT hive.hivemind_app table.
    hive_rowid BIGINT NOT NULL DEFAULT nextval('hive.hivemind_app_hive_rowid_seq'::regclass),

    post_id INT NOT NULL
  , tag_id INT
  , CONSTRAINT hive_post_tags_fk1 FOREIGN KEY( post_id ) REFERENCES hivemind_app.hive_posts(id) DEFERRABLE
  , CONSTRAINT hive_post_tags_fk2 FOREIGN KEY( tag_id ) REFERENCES hivemind_app.hive_tag_data(id) DEFERRABLE
);

--- This index is critical due to migration process which must be done incrementally
CREATE UNIQUE INDEX IF NOT EXISTS hive_post_tags_tag_id_post_id_idx
    ON hivemind_app.hive_post_tags USING btree (tag_id, post_id DESC);

ALTER TABLE hivemind_app.hive_state ADD COLUMN IF NOT EXISTS hivemind_git_rev TEXT NOT NULL DEFAULT '';
ALTER TABLE hivemind_app.hive_state ADD COLUMN IF NOT EXISTS hivemind_git_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT  NOW();
ALTER TABLE hivemind_app.hive_state ADD COLUMN IF NOT EXISTS hivemind_version TEXT NOT NULL DEFAULT '';

-- Crash recovery: high-water mark for payout idempotency
ALTER TABLE hivemind_app.hive_posts ADD COLUMN IF NOT EXISTS last_payout_block INTEGER NOT NULL DEFAULT 0;

-- Superseded: database_api.list_votes by_voter_comment pages on hive_votes_voter_id_author_id_permlink_id_uk
DROP INDEX IF EXISTS hivemind_app.hive_votes_voter_id_post_id_idx;

-- Community moderation audit log; indexes created before registering so HAF records them as 'created'
CREATE TABLE IF NOT EXISTS hivemind_app.hive_moderation_log (
    id BIGSERIAL PRIMARY KEY,
    community_id INTEGER NOT NULL,
    action SMALLINT NOT NULL,
    actor_id INTEGER NOT NULL,
    target_account_id INTEGER,
    target_post_id INTEGER,
    old_value VARCHAR(256),
    new_value VARCHAR(256),
    notes VARCHAR(256),
    block_num INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL
);
CREATE INDEX IF NOT EXISTS hive_moderation_log_community_id_created_at_idx ON hivemind_app.hive_moderation_log (community_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS hive_moderation_log_actor_id_created_at_idx ON hivemind_app.hive_moderation_log (actor_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS hive_moderation_log_target_account_id_idx ON hivemind_app.hive_moderation_log (target_account_id) WHERE target_account_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS hive_moderation_log_block_num_idx ON hivemind_app.hive_moderation_log (block_num);
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_moderation_log_community_id_created_at_idx ON hivemind_app.hive_moderation_log (community_id, created_at DESC, id DESC)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_moderation_log_actor_id_created_at_idx ON hivemind_app.hive_moderation_log (actor_id, created_at DESC, id DESC)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_moderation_log_target_account_id_idx ON hivemind_app.hive_moderation_log (target_account_id) WHERE target_account_id IS NOT NULL');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_moderation_log_block_num_idx ON hivemind_app.hive_moderation_log (block_num)');

-- Autovacuum the append-mostly tables every 100,000 inserts, keeping their visibility maps current for index-only
-- scans. Same list as hive/db/schema.py's reset_autovac, which sets them on a fresh install.
ALTER TABLE hivemind_app.hive_votes SET (autovacuum_vacuum_insert_scale_factor = 0, autovacuum_vacuum_insert_threshold = 100000);
ALTER TABLE hivemind_app.hive_post_data SET (autovacuum_vacuum_insert_scale_factor = 0, autovacuum_vacuum_insert_threshold = 100000);
ALTER TABLE hivemind_app.hive_permlink_data SET (autovacuum_vacuum_insert_scale_factor = 0, autovacuum_vacuum_insert_threshold = 100000);
ALTER TABLE hivemind_app.hive_post_tags SET (autovacuum_vacuum_insert_scale_factor = 0, autovacuum_vacuum_insert_threshold = 100000);
ALTER TABLE hivemind_app.hive_feed_cache SET (autovacuum_vacuum_insert_scale_factor = 0, autovacuum_vacuum_insert_threshold = 100000);

RESET ROLE;

-- HAF has no per-index deregistration and applications cannot write hafd.indexes_constraints, so this runs as
-- the admin. Mirrors hive.remove_index_dependencies for one index; a left-over registration would recreate it.
UPDATE hafd.indexes_constraints
SET contexts = array_remove(contexts, (SELECT id FROM hafd.contexts WHERE name = 'hivemind_app'))
WHERE table_name = 'hivemind_app.hive_votes' AND index_constraint_name = 'hive_votes_voter_id_post_id_idx';
DELETE FROM hafd.indexes_constraints
WHERE table_name = 'hivemind_app.hive_votes' AND index_constraint_name = 'hive_votes_voter_id_post_id_idx' AND cardinality(contexts) = 0;

-- Superseded by follows_following_follower_name_idx, which has the same leading column.
UPDATE hafd.indexes_constraints
SET contexts = array_remove(contexts, (SELECT id FROM hafd.contexts WHERE name = 'hivemind_app'))
WHERE table_name = 'hivemind_app.follows' AND index_constraint_name = 'follows_following_idx';
DELETE FROM hafd.indexes_constraints
WHERE table_name = 'hivemind_app.follows' AND index_constraint_name = 'follows_following_idx' AND cardinality(contexts) = 0;
