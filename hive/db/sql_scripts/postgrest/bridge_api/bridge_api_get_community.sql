DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_community;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_community(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _name TEXT;
  _observer TEXT;
BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"name","observer"}', '{"string", "string"}');
  --- name
  _name = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'name', 0, True);
  _name = hivemind_postgrest_utilities.valid_community(_name);
  --- observer
  _observer = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'observer', 1, False);
  IF _observer IS NULL THEN
    _observer = '';
  ELSE
    _observer = hivemind_postgrest_utilities.valid_account(_observer);
  END IF;

  RETURN (
    SELECT to_json(row) FROM (
      SELECT * FROM hivemind_postgrest_utilities.get_community(_name::TEXT, _observer::TEXT)
    ) row );
END
$$
;