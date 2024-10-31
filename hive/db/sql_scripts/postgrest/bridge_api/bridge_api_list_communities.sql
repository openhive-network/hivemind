DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_list_communities;
CREATE FUNCTION hivemind_endpoints.bridge_api_list_communities(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
    _last TEXT;
    _limit INTEGER;
    _sort TEXT;
    _search TEXT;
    _observer TEXT;
    _response JSONB;
BEGIN
    PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"last", "limit", "query", "sort", "observer"}', '{"string", "number", "string", "string", "string"}');

    _last := COALESCE(hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'last', 0, False), '');
    _last := hivemind_postgrest_utilities.valid_community(_last, True);

    _limit := hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'limit', 1, False);
    _limit := hivemind_postgrest_utilities.valid_number(_limit, 100, 1, 100, 'limit');

    _search := hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'query', 2, False);

    _sort := COALESCE(hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'sort', 3, False), 'rank');
    _sort := hivemind_postgrest_utilities.validate_community_sort_type(_sort);

    _observer := hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'observer', 4, False);
    _observer := hivemind_postgrest_utilities.valid_account(_observer, True);

    CASE
        WHEN _sort = 'rank' THEN
            WITH communities AS (
                SELECT * FROM hivemind_app.bridge_list_communities_by_rank(_observer, _last, _search, _limit)
            )
            SELECT to_jsonb(array_agg(hivemind_postgrest_utilities.prepare_json_for_communities((communities).list_communities) ORDER BY rank ASC))
            INTO _response
            FROM communities;
        WHEN _sort = 'new' THEN
            WITH communities AS (
                SELECT * FROM hivemind_app.bridge_list_communities_by_new(_observer, _last, _search, _limit)
            )
            SELECT to_jsonb(array_agg(hivemind_postgrest_utilities.prepare_json_for_communities(communities) ORDER BY id DESC))
            INTO _response
            FROM communities;
        WHEN _sort = 'subs' THEN
            WITH communities AS (
                SELECT * FROM hivemind_app.bridge_list_communities_by_subs(_observer, _last, _search, _limit)
            )
            SELECT to_jsonb(array_agg(hivemind_postgrest_utilities.prepare_json_for_communities(communities) ORDER BY subscribers DESC, id DESC ))
            INTO _response
            FROM communities;
    END CASE;

    RETURN COALESCE(_response, '[]'::JSONB);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.prepare_json_for_communities;
CREATE FUNCTION hivemind_postgrest_utilities.prepare_json_for_communities(community_data hivemind_app.bridge_api_list_communities)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
AS
$BODY$
DECLARE
    _json_response JSONB;
BEGIN
    IF community_data.title IS NULL THEN
        community_data.title := community_data.name;
    END IF;

    _json_response := to_jsonb(community_data);

    IF community_data.admins[1] IS NULL THEN
        _json_response := _json_response - 'admins';
    END IF;

    RETURN _json_response;
END;
$BODY$;