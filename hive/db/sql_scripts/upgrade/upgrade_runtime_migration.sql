
START TRANSACTION;

DO
$BODY$
BEGIN
SET work_mem='2GB';
IF EXISTS(SELECT * FROM hivemind_app.hive_db_data_migration WHERE migration = 'Reputation calculation') THEN
  RAISE NOTICE 'Performing initial account reputation calculation...';
  PERFORM hivemind_app.update_account_reputations(NULL, NULL, True);
ELSE
  RAISE NOTICE 'Skipping initial account reputation calculation...';
END IF;
END
$BODY$;

COMMIT;

START TRANSACTION;

DO
$BODY$
BEGIN
IF EXISTS(SELECT * FROM hivemind_app.hive_db_data_migration WHERE migration = 'hive_posts_api_helper fill') THEN
  RAISE NOTICE 'Performing initial hivemind_app.hive_posts_api_helper collection...';
    SET work_mem='2GB';
    TRUNCATE TABLE hivemind_app.hive_posts_api_helper;
    DROP INDEX IF EXISTS hivemind_app.hive_posts_api_helper_author_permlink_idx;
    DROP INDEX IF EXISTS hivemind_app.hive_posts_api_helper_author_s_permlink_idx;
    PERFORM hivemind_app.update_hive_posts_api_helper(NULL, NULL);
    CREATE INDEX IF NOT EXISTS hive_posts_api_helper_author_s_permlink_idx ON hivemind_app.hive_posts_api_helper (author_s_permlink);
ELSE
  RAISE NOTICE 'Skipping initial hivemind_app.hive_posts_api_helper collection...';
END IF;
END
$BODY$;

COMMIT;

START TRANSACTION;
DO
$BODY$
BEGIN
IF EXISTS(SELECT * FROM hivemind_app.hive_db_data_migration WHERE migration = 'hive_mentions fill') THEN
  RAISE NOTICE 'Performing initial post body mentions collection...';
  SET work_mem='2GB';
  DROP INDEX IF EXISTS hivemind_app.hive_mentions_block_num_idx;
  PERFORM hivemind_app.update_hive_posts_mentions(0, (SELECT hb.num FROM hivemind_app.hive_blocks hb ORDER BY hb.num DESC LIMIT 1) );
  CREATE INDEX IF NOT EXISTS hive_mentions_block_num_idx ON hivemind_app.hive_mentions (block_num);
ELSE
  RAISE NOTICE 'Skipping initial post body mentions collection...';
END IF;
END
$BODY$;

COMMIT;

START TRANSACTION;

DO
$BODY$
BEGIN
IF EXISTS hivemind_app.(SELECT * FROM hivemind_app.hive_db_data_migration WHERE migration = 'update_posts_rshares( 0, head_block_number) execution') THEN
  RAISE NOTICE 'Performing posts rshares, hot and trend recalculation on range ( 0, head_block_number)...';
  SET work_mem='2GB';
  PERFORM hivemind_app.update_posts_rshares(0, (SELECT hb.num FROM hivemind_app.hive_blocks hb ORDER BY hb.num DESC LIMIT 1) );
  DELETE FROM hivemind_app.hive_db_data_migration WHERE migration = 'update_posts_rshares( 0, head_block_number) execution';
ELSE
  RAISE NOTICE 'Skipping update_posts_rshares( 0, head_block_number) recalculation...';
END IF;
END
$BODY$;

COMMIT;

START TRANSACTION;
DO
$BODY$
BEGIN
IF EXISTS hivemind_app.(SELECT * FROM hivemind_app.hive_db_data_migration WHERE migration = 'update_hive_posts_children_count execution') THEN
  RAISE NOTICE 'Performing initial post children count execution ( 0, head_block_number)...';
  SET work_mem='2GB';
  update hivemind_app.hive_posts set children = 0 where children != 0;
  PERFORM hivemind_app.update_all_hive_posts_children_count();
  DELETE FROM hivemind_app.hive_db_data_migration WHERE migration = 'update_hive_posts_children_count execution';
ELSE
  RAISE NOTICE 'Skipping initial post children count execution ( 0, head_block_number) recalculation...';
END IF;
END
$BODY$;
COMMIT;

START TRANSACTION;
DO
$BODY$
BEGIN
IF EXISTS hivemind_app.(SELECT * FROM hivemind_app.hive_db_data_migration WHERE migration = 'update_hive_post_mentions refill execution') THEN
  RAISE NOTICE 'Performing hivemind_app.hive_mentions refill...';
  SET work_mem='2GB';
  TRUNCATE TABLE hivemind_app.hive_mentions RESTART IDENTITY;
  PERFORM hivemind_app.update_hive_posts_mentions(0, (select max(num) from hivemind_app.hive_blocks));
  DELETE FROM hivemind_app.hive_db_data_migration WHERE migration = 'update_hive_post_mentions refill execution';
ELSE
  RAISE NOTICE 'Skipping hivemind_app.hive_mentions refill...';
END IF;

END
$BODY$;
COMMIT;

START TRANSACTION;
DO
$BODY$
BEGIN
-- Also covers previous changes at a80c7642a1f3b08997af7e8a9915c13d34b7f0e0
-- Also covers previous changes at b100db27f37dda3c869c2756d99ab2856f7da9f9
-- Also covers previous changes at bd83414409b7624e2413b97a62fa7d97d83edd86
IF NOT EXISTS (SELECT * FROM hivemind_app.hive_db_patch_level WHERE patched_to_revision = '1cc9981679157e4e54e5e4a74cca1feb5d49296d')
THEN
  RAISE NOTICE 'Performing notification cache initial fill...';
  SET work_mem='2GB';
  PERFORM hivemind_app.update_notification_cache(NULL, NULL, False);
  DELETE FROM hivemind_app.hive_db_data_migration WHERE migration = 'Notification cache initial fill';
ELSE
  RAISE NOTICE 'Skipping notification cache initial fill...';
END IF;

END
$BODY$;
COMMIT;


START TRANSACTION;

DO
$BODY$
BEGIN
SET work_mem='2GB';
IF NOT EXISTS(SELECT * FROM hivemind_app.hive_db_patch_level WHERE patched_to_revision = 'cce7fe54a2242b7a80354ee7e50e5b3275a2b039') THEN
  RAISE NOTICE 'Performing reputation livesync recalculation...';
  --- reputations have to be recalculated from scratch.
  UPDATE hivemind_app.hive_accounts SET reputation = 0, is_implicit = True;
  PERFORM hivemind_app.update_account_reputations(NULL, NULL, True);
  INSERT INTO hivemind_app.hive_db_vacuum_needed
  (vacuum_needed)
  values
  (True)
  ;
ELSE
  RAISE NOTICE 'Skipping reputation livesync recalculation...';
END IF;
END
$BODY$;

COMMIT;

START TRANSACTION;

DO
$BODY$
BEGIN
SET work_mem='2GB';
IF NOT EXISTS(SELECT * FROM hivemind_app.hive_db_patch_level WHERE patched_to_revision = '33dd5e52673335284c6aa28ee89a069f83bd2dc6') THEN
  RAISE NOTICE 'Performing reputation data cleanup...';
  PERFORM hivemind_app.truncate_account_reputation_data('30 days'::interval);
  INSERT INTO hivemind_app.hive_db_vacuum_needed
    (vacuum_needed)
  values
    (True)
  ;
ELSE
  RAISE NOTICE 'Skipping reputation data cleanup...';
END IF;
END
$BODY$;

COMMIT;

TRUNCATE TABLE hivemind_app.hive_db_data_migration;
