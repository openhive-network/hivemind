DROP FUNCTION IF EXISTS hivemind_app.condenser_get_names_by_reblogged;

CREATE FUNCTION hivemind_app.condenser_get_names_by_reblogged( in _author VARCHAR, in _permlink VARCHAR )
RETURNS TABLE(
    names hivemind_app.hive_accounts.name%TYPE
)
AS
$function$
DECLARE
  __post_id INT;
BEGIN
  __post_id = hivemind_app.find_comment_id( _author, _permlink, True );

  RETURN QUERY SELECT
    ha.name
  FROM hivemind_app.hive_accounts ha
  JOIN hivemind_app.hive_feed_cache hfc ON ha.id = hfc.account_id
  WHERE hfc.post_id = __post_id
  ORDER BY ha.name
  ;

END
$function$
language plpgsql STABLE;
