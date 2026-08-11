SET ROLE hivemind;

--- Put runtime data migration code here

DO
$$
BEGIN

IF EXISTS (SELECT column_name FROM information_schema.columns WHERE table_name='hivemind_app.hive_posts' and column_name='tags_ids') THEN
  RAISE NOTICE 'Performing TAG-IDs migration';

WITH data_source AS
(
  SELECT p.id AS post_id, unnest(p.tags_ids) AS tag_id
  FROM hivemind_app.hive_posts p
  EXCEPT
  SELECT pt.post_id, pt.tag_id
  FROM hivemind_app.hive_post_tags pt
)
INSERT INTO hivemind_app.hive_post_tags
(post_id, tag_id)
SELECT ds.post_id, ds.tag_id
FROM data_source ds
;

CREATE INDEX IF NOT EXISTS hive_post_tags_idx
ON hivemind_app.hive_post_tags USING btree(post_id, tag_id)
TABLESPACE haf_tablespace
;

ALTER TABLE hivemind_app.hive_post_tags INHERIT hive.hivemind_app;

ANALYZE VERBOSE hivemind_app.hive_post_tags;
ELSE
  RAISE NOTICE 'TAG-IDs migration skipped';
END IF;
END
$$
;

--- #339: raise the MASSIVE_WITHOUT_INDEXES stage distance from one week (201600)
--- to 2M blocks on existing contexts. Stage definitions are baked into the
--- context at app_create_context time, so upgrades must rewrite them here.
--- Keep in sync with MASSIVE_WITHOUT_INDEXES_THRESHOLD_BLOCKS in hive/conf.py
--- and the stage array in hive/indexer/hive_db/haf_functions.py.
--- Idempotent: only rewrites when the stored stages differ.
UPDATE hafd.contexts
SET stages = ARRAY[
      hive.stage('MASSIVE_WITHOUT_INDEXES', 2000000, 1000, '20 seconds'),
      hive.stage('MASSIVE_WITH_INDEXES', 101, 1000, '20 seconds'),
      hive.live_stage()
    ]::hive.application_stages
WHERE name = 'hivemind_app'
  AND stages IS DISTINCT FROM ARRAY[
      hive.stage('MASSIVE_WITHOUT_INDEXES', 2000000, 1000, '20 seconds'),
      hive.stage('MASSIVE_WITH_INDEXES', 101, 1000, '20 seconds'),
      hive.live_stage()
    ]::hive.application_stages;

--- Must be at the end
TRUNCATE TABLE hivemind_app.hive_db_data_migration;

RESET ROLE;
