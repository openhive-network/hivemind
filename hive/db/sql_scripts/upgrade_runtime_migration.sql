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

IF EXISTS(SELECT * FROM hive_db_data_migration WHERE migration = 'hive_posts_api_helper fill') THEN
  RAISE NOTICE 'Performing initial hive_posts_api_helper collection...';
  SET work_mem='2GB';
  PERFORM update_hive_posts_api_helper(NULL, NULL);

    CREATE INDEX hive_posts_api_helper_author_permlink_idx ON hive_posts_api_helper
      (author COLLATE pg_catalog."C" ASC NULLS LAST, permlink COLLATE pg_catalog."C" ASC NULLS LAST)
    ;
ELSE
  RAISE NOTICE 'Skipping initial hive_posts_api_helper collection...';
END IF;

IF EXISTS(SELECT * FROM hive_db_data_migration WHERE migration = 'hive_mentions fill') THEN
  RAISE NOTICE 'Performing initial post body mentions collection...';
  SET work_mem='2GB';

  PERFORM update_hive_posts_mentions(0, (SELECT hb.num FROM hive_blocks hb ORDER BY hb.num DESC LIMIT 1) );
  CREATE INDEX IF NOT EXISTS hive_mentions_block_num_idx ON hive_mentions (block_num);
ELSE
  RAISE NOTICE 'Skipping initial post body mentions collection...';
END IF;


IF EXISTS (SELECT * FROM hive_db_data_migration WHERE migration = 'update_hot_and_trending_for_blocks( 0, head_block_number) execution') THEN
  RAISE NOTICE 'Performing update_hot_and_trending_for_blocks( 0, head_block_number) recalculation...';
  SET work_mem='2GB';
  PERFORM update_hot_and_trending_for_blocks(0, (SELECT hb.num FROM hive_blocks hb ORDER BY hb.num DESC LIMIT 1) );
ELSE
  RAISE NOTICE 'Skipping update_hot_and_trending_for_blocks( 0, head_block_number) recalculation...';
END IF;

END
$BODY$;

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
(now(), '8d0b673e7c40c05d2b8ae74ccf32adcb6b11f906')  -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/265
) ds (patch_date, patch_revision)
where not exists (select null from hive_db_patch_level hpl where hpl.patched_to_revision = ds.patch_revision);

;

