
DROP FUNCTION IF EXISTS hivemind_app.delete_reblog_feed_cache(character varying,character varying,character varying)
;

CREATE OR REPLACE FUNCTION hivemind_app.delete_reblog_feed_cache(
  in _author hivemind_app.hive_accounts.name%TYPE,
  in _permlink hivemind_app.hive_permlink_data.permlink%TYPE,
  in _account hivemind_app.hive_accounts.name%TYPE)
RETURNS INTEGER
LANGUAGE plpgsql
AS
$function$
DECLARE
  __account_id INT;
  __post_id INT;
BEGIN

  __account_id = hivemind_app.find_account_id( _account, False );
  __post_id = hivemind_app.find_comment_id( _author, _permlink, False );

  IF __post_id = 0 THEN
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
