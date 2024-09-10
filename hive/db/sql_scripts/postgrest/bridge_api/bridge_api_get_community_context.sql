DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_community_context;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_community_context(IN _json_is_object BOOLEAN, IN _method_is_call BOOLEAN, IN _params JSON)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  _name TEXT;
  _account TEXT;
BEGIN
  --- name
  _name = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'name', 0, True);
  _name = hivemind_postgrest_utilities.valid_community(_name);
  --- account
  _account = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'account', 1, True);
  _account = hivemind_postgrest_utilities.valid_observer(_account);
  
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _method_is_call, _params, '{"name","account"}', '{"string", "string"}');

  RETURN (
    SELECT to_json(row) FROM (
      SELECT * FROM hivemind_postgrest_utilities.get_community_context(_name::TEXT, _account::TEXT)
    ) row );
END
$$
;