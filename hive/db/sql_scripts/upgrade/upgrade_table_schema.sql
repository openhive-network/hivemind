do $$
BEGIN
  ASSERT (SELECT setting FROM pg_settings where name='join_collapse_limit' and source='database')::int = 16, 'Bad optimizer settings, use install_app.sh script to setup target database correctly';
  ASSERT (SELECT setting FROM pg_settings where name='from_collapse_limit' and source='database')::int = 16, 'Bad optimizer settings, use install_app.sh script to setup target database correctly';
  ASSERT (SELECT setting FROM pg_settings where name='jit' and source='database')::BOOLEAN = False, 'Bad optimizer settings, use install_app.sh script to setup target database correctly';
END$$;

-- In case such tables have been created directly by admin, drop them first to allow correct creation and access during upgrade process.
DROP TABLE IF EXISTS hivemind_app.hive_db_vacuum_needed;
DROP TABLE IF EXISTS hivemind_app.hive_db_data_migration;

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

RESET ROLE;
