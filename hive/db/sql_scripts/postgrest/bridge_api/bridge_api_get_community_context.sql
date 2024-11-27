DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_community_context;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_community_context(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _community_id INT;
  _account_id INT;
BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"name": "string", "account": "string"}', 0, '{"name": "given community name is not valid", "account": "invalid account name type"}');

  _community_id = 
    hivemind_postgrest_utilities.find_community_id(
      hivemind_postgrest_utilities.valid_community(
        hivemind_postgrest_utilities.parse_argument_from_json(_params, 'name', True)
      ),
    True);
  
  _account_id = 
    hivemind_postgrest_utilities.find_account_id(
      hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_argument_from_json(_params, 'account', True),
      True),
    True);
  
  IF _account_id = 0 THEN
    RETURN '{}'::JSONB;
  END IF;

  RETURN hivemind_postgrest_utilities.get_community_context(_account_id, _community_id);
END
$$
;