DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_community_context;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_community_context(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _name TEXT;
  _account TEXT;
BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"name","account"}', '{"string", "string"}');
  --- name
  _name = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'name', 0, True);
  _name = hivemind_postgrest_utilities.valid_community(_name);
  --- account
  _account = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'account', 1, True);
  _account = hivemind_postgrest_utilities.valid_account(_account);

  RETURN (
    SELECT to_json(row) FROM (
      SELECT * FROM hivemind_postgrest_utilities.get_community_context(_name::TEXT, _account::TEXT)
    ) row );
END
$$
;