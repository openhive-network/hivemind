
DROP FUNCTION IF EXISTS delete_reblog_feed_cache(character varying,character varying,character varying)
;

CREATE OR REPLACE FUNCTION delete_reblog_feed_cache(
  in _author hive_accounts.name%TYPE,
  in _permlink hive_permlink_data.permlink%TYPE,
  in _account hive_accounts.name%TYPE)
RETURNS INTEGER
LANGUAGE plpgsql
AS
$function$
DECLARE
  __account_id INT;
  __post_id INT;
BEGIN

  __account_id = find_account_id( _account, False );
  __post_id = find_comment_id( _author, _permlink, False );

  IF __post_id = 0 THEN
    RETURN 0;
  END IF;

  DELETE FROM hive_reblogs
  WHERE blogger_id = __account_id AND post_id = __post_id;

  DELETE FROM hive_feed_cache
  WHERE account_id = __account_id AND post_id = __post_id;

  RETURN 1;
END
$function$
;
