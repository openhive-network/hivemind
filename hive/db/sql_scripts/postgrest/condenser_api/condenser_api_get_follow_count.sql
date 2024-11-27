DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_follow_count;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_follow_count(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _account TEXT;
  _account_id INT;
BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"account"}', '{"string"}');
  _account = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'account', 0, True);
  _account_id = hivemind_postgrest_utilities.find_account_id(hivemind_postgrest_utilities.valid_account(_account, False), True);
  RETURN (
    SELECT to_jsonb(row) FROM (     -- condenser_api_get_follow_count
      SELECT name AS account, ha.following AS following_count, ha.followers AS follower_count FROM hivemind_app.hive_accounts ha WHERE ha.id = _account_id
    ) row );
END;
$$
;