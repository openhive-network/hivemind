DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_follow_count;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_follow_count(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _account TEXT;
  _account_id INT;
BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"account": "string"}', 1, NULL);
  _account = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'account', True);
  _account_id = hivemind_postgrest_utilities.find_account_id(hivemind_postgrest_utilities.valid_account(_account, False), True);
  RETURN (
    SELECT to_jsonb(row) FROM (     -- condenser_api_get_follow_count
      SELECT name AS account, ha.following AS following_count, ha.followers AS follower_count FROM hivemind_app.hive_accounts ha WHERE ha.id = _account_id
    ) row );
END;
$$
;