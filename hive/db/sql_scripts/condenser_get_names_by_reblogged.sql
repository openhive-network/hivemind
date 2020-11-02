DROP FUNCTION IF EXISTS condenser_get_names_by_reblogged;

CREATE FUNCTION condenser_get_names_by_reblogged( in _author VARCHAR, in _permlink VARCHAR )
RETURNS TABLE(
    names hive_accounts.name%TYPE
)
AS
$function$
DECLARE
  __post_id INT;
BEGIN
  __post_id = find_comment_id( _author, _permlink, True );

  RETURN QUERY SELECT
    name
  FROM hive_accounts ha
  JOIN hive_feed_cache hfc ON ha.id = hfc.account_id
  WHERE hfc.post_id = __post_id;

END
$function$
language plpgsql STABLE;
