
START TRANSACTION;

DO
$BODY$
BEGIN
SET work_mem='2GB';
IF EXISTS(SELECT * FROM hive_db_data_migration WHERE migration = 'Reputation calculation') THEN
  RAISE NOTICE 'Performing initial account reputation calculation...';
  PERFORM update_account_reputations(NULL, NULL);
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
IF EXISTS(SELECT * FROM hive_db_data_migration WHERE migration = 'hive_posts_api_helper fill') THEN
  RAISE NOTICE 'Performing initial hive_posts_api_helper collection...';
    SET work_mem='2GB';
    TRUNCATE TABLE hive_posts_api_helper;
    DROP INDEX IF EXISTS hive_posts_api_helper_author_permlink_idx;
    DROP INDEX IF EXISTS hive_posts_api_helper_author_s_permlink_idx;
    PERFORM update_hive_posts_api_helper(NULL, NULL);
    CREATE INDEX IF NOT EXISTS hive_posts_api_helper_author_s_permlink_idx ON hive_posts_api_helper (author_s_permlink);
ELSE
  RAISE NOTICE 'Skipping initial hive_posts_api_helper collection...';
END IF;
END
$BODY$;

COMMIT;

START TRANSACTION;
DO
$BODY$
BEGIN
IF EXISTS(SELECT * FROM hive_db_data_migration WHERE migration = 'hive_mentions fill') THEN
  RAISE NOTICE 'Performing initial post body mentions collection...';
  SET work_mem='2GB';
  DROP INDEX IF EXISTS hive_mentions_block_num_idx;
  PERFORM update_hive_posts_mentions(0, (SELECT hb.num FROM hive_blocks hb ORDER BY hb.num DESC LIMIT 1) );
  CREATE INDEX IF NOT EXISTS hive_mentions_block_num_idx ON hive_mentions (block_num);
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
IF EXISTS (SELECT * FROM hive_db_data_migration WHERE migration = 'update_posts_rshares( 0, head_block_number) execution') THEN
  RAISE NOTICE 'Performing posts rshares, hot and trend recalculation on range ( 0, head_block_number)...';
  SET work_mem='2GB';
  PERFORM update_posts_rshares(0, (SELECT hb.num FROM hive_blocks hb ORDER BY hb.num DESC LIMIT 1) );
  DELETE FROM hive_db_data_migration WHERE migration = 'update_posts_rshares( 0, head_block_number) execution';
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
IF EXISTS (SELECT * FROM hive_db_data_migration WHERE migration = 'update_hive_posts_children_count execution') THEN
  RAISE NOTICE 'Performing initial post children count execution ( 0, head_block_number)...';
  SET work_mem='2GB';
  update hive_posts set children = 0 where children != 0;
  PERFORM update_all_hive_posts_children_count();
  DELETE FROM hive_db_data_migration WHERE migration = 'update_hive_posts_children_count execution';
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
IF EXISTS (SELECT * FROM hive_db_data_migration WHERE migration = 'update_hive_post_mentions refill execution') THEN
  RAISE NOTICE 'Performing hive_mentions refill...';
  SET work_mem='2GB';
  TRUNCATE TABLE hive_mentions RESTART IDENTITY;
  PERFORM update_hive_posts_mentions(0, (select max(num) from hive_blocks));
  DELETE FROM hive_db_data_migration WHERE migration = 'update_hive_post_mentions refill execution';
ELSE
  RAISE NOTICE 'Skipping hive_mentions refill...';
END IF;

END
$BODY$;
COMMIT;

START TRANSACTION;
DO
$BODY$
BEGIN
IF EXISTS (SELECT * FROM hive_db_data_migration WHERE migration = 'Notification cache initial fill') THEN
  RAISE NOTICE 'Performing notification cache initial fill...';
  SET work_mem='2GB';
  PERFORM update_notification_cache(NULL, NULL, False);
  DELETE FROM hive_db_data_migration WHERE migration = 'Notification cache initial fill';
ELSE
  RAISE NOTICE 'Skipping notification cache initial fill...';
END IF;

END
$BODY$;
COMMIT;

START TRANSACTION;

TRUNCATE TABLE hive_db_data_migration;

insert into hive_db_patch_level
(patch_date, patched_to_revision)
select ds.patch_date, ds.patch_revision
from
(
values
(now(), '7b8def051be224a5ebc360465f7a1522090c7125'),
(now(), 'e17bfcb08303cbf07b3ce7d1c435d59a368b4a9e'),
(now(), '0be8e6e8b2121a8f768113e35e47725856c5da7c'), -- update_hot_and_trending_for_blocks fix, https://gitlab.syncad.com/hive/hivemind/-/merge_requests/247
(now(), '26c2f1862770178d4575ec09e9f9c225dcf3d206'), -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/252
(now(), 'e8b65adf22654203f5a79937ff2a95c5c47e10c5'), -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/251
(now(), '8d0b673e7c40c05d2b8ae74ccf32adcb6b11f906'), -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/265
-- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/281
-- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/282
-- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/257
-- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/251
-- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/265
--
(now(), '45c2883131472cc14a03fe4e355ba1435020d720'),
(now(), '7cfc2b90a01b32688075b22a6ab173f210fc770f'), -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/286
(now(), 'f2e5f656a421eb1dd71328a94a421934eda27a87')  -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/275
,(now(), '4cdf5d19f6cfcb73d3fa504cac9467c4df31c02e') -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/295
--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/294
--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/298
--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/301
--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/297
--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/302
,(now(), '166327bfa87beda588b20bfcfa574389f4100389')
,(now(), '88e62bdf1fcc47809fec84424cf98c71ce87ca89') -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/310
,(now(), 'f8ecf376da5e0efef64b79f91e9803eac8b163a4') -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/289
,(now(), '0e3c8700659d98b45f1f7146dc46a195f905fc2d') -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/306 update posts children count fix
,(now(), '9e126e9d762755f2b9a0fd68f076c9af6bb73b76') -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/314 mentions fix
,(now(), '033619277eccea70118a5b8dc0c73b913da0025f') -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/326 https://gitlab.syncad.com/hive/hivemind/-/merge_requests/322 posts rshares recalc
,(now(), '1847c75702384c7e34c624fc91f24d2ef20df91d') -- latest version of develop containing included changes.
,(now(), '1f23e1326f3010bc84353aba82d4aa7ff2f999e4') -- hive_posts_author_id_created_at_idx index def. to speedup hive_accounts_info_view.
,(now(), '2a274e586454968a4f298a855a7e60394ed90bde') -- get_number_of_unread_notifications speedup https://gitlab.syncad.com/hive/hivemind/-/merge_requests/348/diffs
,(now(), '431fdaead7dcd69e4d2a45e7ce8a3186b8075515') -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/367
,(now(), 'cc7bb174d40fe1a0e2221d5d7e1c332c344dca34') -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/372
) ds (patch_date, patch_revision)
where not exists (select null from hive_db_patch_level hpl where hpl.patched_to_revision = ds.patch_revision);

COMMIT;

;
