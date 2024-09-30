DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_reblogged_by;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_reblogged_by(IN _json_is_object BOOLEAN, IN _params JSON)
RETURNS JSON
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _author TEXT;
  _permlink TEXT;
  _post_id INT;
  _account_id INT;
BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"author","permlink"}','{"string","string"}');
  _author = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'author', 0, True);
  _permlink = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'permlink', 1, True);
  _account_id = hivemind_postgrest_utilities.find_account_id( hivemind_postgrest_utilities.valid_account(_author, False), True );
  _post_id = hivemind_postgrest_utilities.find_comment_id( _author, hivemind_postgrest_utilities.valid_permlink(_permlink, False), True );
  RETURN (
    SELECT to_json(result.array) FROM (
      SELECT ARRAY (SELECT ha.name FROM hivemind_app.hive_accounts ha JOIN hivemind_app.hive_feed_cache hfc ON ha.id = hfc.account_id WHERE hfc.post_id = _post_id AND hfc.account_id <> _account_id ORDER BY ha.name)
  ) result );
END;
$$
;