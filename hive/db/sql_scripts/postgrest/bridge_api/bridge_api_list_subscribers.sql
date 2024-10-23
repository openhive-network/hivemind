DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_list_subscribers;
CREATE FUNCTION hivemind_endpoints.bridge_api_list_subscribers(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
    _community TEXT;
    _last TEXT := '';
    _limit INTEGER := 100;
    _response JSONB;
BEGIN
    PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"community", "last", "limit"}', '{"string", "string", "number"}', 1);

    _community = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'community', 0, True);
    _community = hivemind_postgrest_utilities.valid_community(_community);

    _last = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'last', 1, False);
    _last = hivemind_postgrest_utilities.valid_account(_last, True);

    _limit = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'limit', 2, False);
    _limit = hivemind_postgrest_utilities.valid_number(_limit, 100, 1, 100, 'limit');

    WITH subscribers AS (
        SELECT
            su.name,
            jsonb_build_array(su.name, su.role, COALESCE(su.title, NULL),
            hivemind_postgrest_utilities.json_date(su.created_at)) AS subs
        FROM hivemind_app.bridge_list_subscribers(
            (_community)::VARCHAR,
            (_last)::VARCHAR,
            (_limit)::INT
        ) su
        ORDER BY su.name ASC
    )
    SELECT jsonb_agg(s.subs)
    INTO _response
    FROM subscribers s;

    RETURN COALESCE(_response, '[]'::JSONB);
END
$$
;