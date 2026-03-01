-- Drop all foreign key constraints from Hivemind tables.

ALTER TABLE hivemind_app.hive_posts DROP CONSTRAINT IF EXISTS hive_posts_fk1;
ALTER TABLE hivemind_app.hive_posts DROP CONSTRAINT IF EXISTS hive_posts_fk2;
ALTER TABLE hivemind_app.hive_posts DROP CONSTRAINT IF EXISTS hive_posts_fk3;

ALTER TABLE hivemind_app.hive_votes DROP CONSTRAINT IF EXISTS hive_votes_fk1;
ALTER TABLE hivemind_app.hive_votes DROP CONSTRAINT IF EXISTS hive_votes_fk2;
ALTER TABLE hivemind_app.hive_votes DROP CONSTRAINT IF EXISTS hive_votes_fk3;
ALTER TABLE hivemind_app.hive_votes DROP CONSTRAINT IF EXISTS hive_votes_fk4;

ALTER TABLE hivemind_app.hive_post_tags DROP CONSTRAINT IF EXISTS hive_post_tags_fk1;
ALTER TABLE hivemind_app.hive_post_tags DROP CONSTRAINT IF EXISTS hive_post_tags_fk2;

ALTER TABLE hivemind_app.hive_reblogs DROP CONSTRAINT IF EXISTS hive_reblogs_fk1;
ALTER TABLE hivemind_app.hive_reblogs DROP CONSTRAINT IF EXISTS hive_reblogs_fk2;

ALTER TABLE hivemind_app.hive_mentions DROP CONSTRAINT IF EXISTS hive_mentions_fk1;
ALTER TABLE hivemind_app.hive_mentions DROP CONSTRAINT IF EXISTS hive_mentions_fk2;
