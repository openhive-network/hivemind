DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_profile;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_profile(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _account TEXT;
  _result JSONB;
BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"account": "string", "observer": "string"}', 1, '{"account": "invalid account name type"}');
  _account = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'account', True);

    _result = hivemind_postgrest_utilities.get_profiles(
        jsonb_build_array(_account),
        hivemind_postgrest_utilities.parse_argument_from_json(_params, 'observer', False)
    );

    RETURN jsonb_array_element(_result, 0);
END
$$
;
