DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_reblogged_by;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_reblogged_by(IN _author TEXT, IN _permlink TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __post_id INT;
  __account_id INT;
BEGIN
  __account_id = hivemind_utilities.find_account_id( hivemind_utilities.valid_account(_author, False), True );
  __post_id = hivemind_utilities.find_comment_id( _author, hivemind_utilities.valid_permlink(_permlink, False), True );
  RETURN (
    SELECT to_json(result.array) FROM (
      SELECT ARRAY (SELECT ha.name FROM hivemind_app.hive_accounts ha JOIN hivemind_app.hive_feed_cache hfc ON ha.id = hfc.account_id WHERE hfc.post_id = __post_id AND hfc.account_id <> __account_id ORDER BY ha.name)
  ) result );
END;
$$
;