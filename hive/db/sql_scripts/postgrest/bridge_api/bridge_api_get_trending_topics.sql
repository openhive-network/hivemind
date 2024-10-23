DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_trending_topics;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_trending_topics(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
    _limit INTEGER := 25;
BEGIN
    PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"limit"}', '{"number"}');

    _limit = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'limit', 0, False);
    _limit = hivemind_postgrest_utilities.valid_number(_limit, 10, 1, 25, 'limit');

    _top_communities = hivemind_postgrest_utilities.list_top_communities(_limit)
    
END
$$
;