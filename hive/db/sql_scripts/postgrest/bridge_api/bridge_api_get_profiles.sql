DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_profiles;
CREATE OR REPLACE FUNCTION hivemind_endpoints.bridge_api_get_profiles(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _accounts JSONB;
BEGIN
    _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"accounts": "array", "observer": "string"}', 1, '{"accounts": "invalid accounts type"}');
    _accounts = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'accounts', True);

   RETURN hivemind_postgrest_utilities.get_profiles(_accounts, hivemind_postgrest_utilities.parse_argument_from_json(_params, 'observer', False));
END
$$
;
