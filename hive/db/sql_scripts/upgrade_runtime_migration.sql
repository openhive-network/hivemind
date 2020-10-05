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
  RAISE NOTICE 'Performing initial post body mentions collection...';
END IF;

END
$BODY$;

TRUNCATE TABLE hive_db_data_migration;

