do $$
BEGIN
  ASSERT (SELECT setting FROM pg_settings where name='join_collapse_limit' and source='database')::int = 16, 'Bad optimizer settings, use install_app.sh script to setup target database correctly';
  ASSERT (SELECT setting FROM pg_settings where name='from_collapse_limit' and source='database')::int = 16, 'Bad optimizer settings, use install_app.sh script to setup target database correctly';
  ASSERT (SELECT setting FROM pg_settings where name='jit' and source='database')::BOOLEAN = False, 'Bad optimizer settings, use install_app.sh script to setup target database correctly';
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

CREATE INDEX IF NOT EXISTS hive_posts_tags_ids_live_post_cond_idx
  ON hivemind_app.hive_posts USING gin
  (tags_ids gin__int_ops)
  TABLESPACE haf_tablespace
  WHERE counter_deleted = 0 AND depth = 0
;

CREATE INDEX IF NOT EXISTS hive_posts_tags_ids_live_cond_idx
  ON hivemind_app.hive_posts USING gin
  (tags_ids gin__int_ops)
  TABLESPACE haf_tablespace
  WHERE counter_deleted = 0
;

DROP INDEX IF EXISTS hive_posts_tags_ids_idx;
DROP INDEX IF EXISTS hive_posts_tags_ids_live_post_cond_idx;
DROP INDEX IF EXISTS hive_posts_tags_ids_live_cond_idx;

CREATE TABLE IF NOT EXISTS hivemind_app.hive_post_tags (
    post_id INT NOT NULL
  , tag_id INT
  , CONSTRAINT hive_post_tags_fk1 FOREIGN KEY( post_id ) REFERENCES hivemind_app.hive_posts(id) DEFERRABLE
  , CONSTRAINT hive_post_tags_fk2 FOREIGN KEY( tag_id ) REFERENCES hivemind_app.hive_tag_data(id) DEFERRABLE
) INHERITS(hive.hivemind_app);

CREATE UNIQUE INDEX IF NOT EXISTS hive_post_tags_tag_id_post_id_idx
    ON hivemind_app.hive_post_tags USING btree (tag_id, post_id DESC);

