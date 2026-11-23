DROP FUNCTION IF EXISTS hivemind_app.delete_reblog_feed_cache(character varying,character varying,character varying)
;
DROP FUNCTION IF EXISTS hivemind_app.delete_reblog_feed_cache(character varying,character varying,character varying,integer)
;

-- Removes _account's reblog of _author/_permlink, the version live at the end of block
-- _last_block (see process_reblogs_from_staging), and its feed cache row.
CREATE OR REPLACE FUNCTION hivemind_app.delete_reblog_feed_cache(
  in _author hivemind_app.hive_accounts.name%TYPE,
  in _permlink hivemind_app.hive_permlink_data.permlink%TYPE,
  in _account hivemind_app.hive_accounts.name%TYPE,
  in _last_block INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
AS
$function$
DECLARE
  __account_id INT;
  __post_id INT;
BEGIN

  __account_id = hivemind_app.find_account_id( _account, False );
  SELECT hp.id INTO __post_id
  FROM hivemind_app.hive_posts hp
  JOIN hivemind_app.hive_accounts ha ON ha.id = hp.author_id
  JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
  WHERE ha.name = _author AND hpd.permlink = _permlink
    AND hp.block_num_created <= _last_block AND (hp.counter_deleted = 0 OR hp.block_num > _last_block);

  IF __post_id IS NULL THEN
    RETURN 0;
  END IF;

  DELETE FROM hivemind_app.hive_reblogs
  WHERE blogger_id = __account_id AND post_id = __post_id;

  DELETE FROM hivemind_app.hive_feed_cache
  WHERE account_id = __account_id AND post_id = __post_id;

  RETURN 1;
END
$function$
;
