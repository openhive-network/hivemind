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

RESET ROLE;

-- HAF has no per-index deregistration and applications cannot write hafd.indexes_constraints, so this runs as
-- the admin. Mirrors hive.remove_index_dependencies for one index; a left-over registration would recreate it.
UPDATE hafd.indexes_constraints
SET contexts = array_remove(contexts, (SELECT id FROM hafd.contexts WHERE name = 'hivemind_app'))
WHERE table_name = 'hivemind_app.hive_votes' AND index_constraint_name = 'hive_votes_voter_id_post_id_idx';
DELETE FROM hafd.indexes_constraints
WHERE table_name = 'hivemind_app.hive_votes' AND index_constraint_name = 'hive_votes_voter_id_post_id_idx' AND cardinality(contexts) = 0;
