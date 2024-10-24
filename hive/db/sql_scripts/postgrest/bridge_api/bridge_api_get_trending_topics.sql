DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_trending_topics;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_trending_topics(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
    _limit INTEGER := 10;
    _observer TEXT;
    result JSONB := '[]';
    tag TEXT;
BEGIN
    PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"limit", "observer"}', '{"number", "string"}');

    _limit = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'limit', 0, False);
    _limit = hivemind_postgrest_utilities.valid_number(_limit, 10, 1, 25, 'limit');

    _observer = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'observer', 1, False);
    PERFORM hivemind_postgrest_utilities.valid_account(_observer, TRUE);

    SELECT jsonb_agg(jsonb_build_array(
                community_data->>0, 
                COALESCE(NULLIF(community_data->>1, ''), community_data->>0)
           )) 
    INTO result
    FROM (
        SELECT list_top_communities AS community_data 
        FROM hivemind_postgrest_utilities.list_top_communities(_limit)
    ) AS subquery;

    IF jsonb_array_length(result) < _limit THEN
        FOR tag IN
            SELECT unnest(ARRAY['photography', 'travel', 'gaming', 'crypto', 'newsteem', 'music', 'food'])
        LOOP
            IF jsonb_array_length(result) < _limit THEN
                result := result || jsonb_agg(jsonb_build_array(tag, '#' || tag));
            ELSE
                EXIT;
            END IF;
        END LOOP;
    END IF;

    RETURN result;
END
$$
;