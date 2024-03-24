SET ROLE hivemind;

--- Put runtime data migration code here

INSERT INTO hivemind_app.hive_post_tags(post_id, tag_id)
SELECT id, unnest(tags_ids)
FROM hivemind_app.hive_posts;

CREATE INDEX IF NOT EXISTS hive_post_tags_idx
ON hivemind_app.hive_post_tags USING btree(post_id, tag_id)
TABLESPACE haf_tablespace
;

--- Must be at the end
TRUNCATE TABLE hivemind_app.hive_db_data_migration;

RESET ROLE;
