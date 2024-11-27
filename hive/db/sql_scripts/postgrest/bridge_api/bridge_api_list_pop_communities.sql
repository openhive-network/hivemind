DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_list_pop_communities;
CREATE FUNCTION hivemind_endpoints.bridge_api_list_pop_communities(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
    _limit INTEGER;
    _response JSONB;
BEGIN
    _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"limit": "number"}', 0, NULL);

    _limit := hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False);
    _limit := hivemind_postgrest_utilities.valid_number(_limit, 25, 1, 25, 'limit');

    SELECT jsonb_agg(jsonb_build_array(name, title) ORDER BY newsubs DESC, id DESC) INTO _response
    FROM hivemind_app.bridge_list_pop_communities(_limit);

    RETURN _response;
END
$$
;