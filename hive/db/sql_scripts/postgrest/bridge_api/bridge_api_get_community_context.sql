DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_community_context;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_community_context(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _community_id INT;
  _account_id INT;
BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"name","account"}', '{"string", "string"}');

  _community_id = 
    hivemind_postgrest_utilities.find_community_id(
      hivemind_postgrest_utilities.valid_community(
        hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'name', 0, True)
      ),
    True);
  
  _account_id = 
    hivemind_postgrest_utilities.find_account_id(
      hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'account', 1, True),
      True),
    True);
  
  IF _account_id = 0 THEN
    RETURN '{}'::JSONB;
  END IF;

  RETURN hivemind_postgrest_utilities.get_community_context(_account_id, _community_id);
END
$$
;