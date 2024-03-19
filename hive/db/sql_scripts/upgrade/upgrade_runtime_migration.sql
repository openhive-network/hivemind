--- Put runtime data migration code here

--- Must be at the end
TRUNCATE TABLE hivemind_app.hive_db_data_migration;


INSERT INTO hivemind_app.hive_post_tags(post_id, tag_id)
SELECT id, unnest(tags_ids)
FROM hivemind_app.hive_posts;

CREATE INDEX IF NOT EXISTS hive_post_tags_idx
ON hivemind_app.hive_post_tags USING btree(post_id, tag_id)
TABLESPACE haf_tablespace
;

CREATE INDEX IF NOT EXISTS hive_post_tags_tag_id_post_id_idx
ON hivemind_app.hive_post_tags USING btree(tag_id, post_id DESC)
TABLESPACE haf_tablespace
;

