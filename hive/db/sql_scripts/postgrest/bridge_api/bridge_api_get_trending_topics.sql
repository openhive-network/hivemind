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
    _lowest_community_rank INTEGER := 2147483647; -- MAX INT
    _fallback_tags_array TEXT[] := ARRAY['food', 'music', 'newsteem', 'crypto', 'gaming', 'travel', 'photography'];
    result JSONB;
BEGIN
    PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"limit", "observer"}', '{"number", "string"}');

    _limit := hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'limit', 0, False);
    _limit := hivemind_postgrest_utilities.valid_number(_limit, 10, 1, 25, 'limit');

    _observer := hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'observer', 1, False);
    PERFORM hivemind_postgrest_utilities.valid_account(_observer, True);

    WITH main_communities AS ( -- bridge_api_get_trending_topics
        SELECT jsonb_build_array(
                    community_data->>0,
                    COALESCE(NULLIF(community_data->>1, ''), community_data->>0)
               ) AS entry,
               rank
        FROM (
            SELECT community_data, rank
            FROM hivemind_postgrest_utilities.list_top_communities(_limit)
        ) AS subquery
    ),
    fallback_tags AS (
        SELECT jsonb_build_array(tag, '#' || tag) AS entry,
               _lowest_community_rank - ROW_NUMBER() OVER (ORDER BY array_position(_fallback_tags_array, tag)) AS rank
        FROM unnest(_fallback_tags_array) AS tag
    ),
    combined_results AS (
        (
            SELECT entry, rank FROM main_communities
            UNION ALL
            SELECT entry, rank FROM fallback_tags
        ) ORDER BY rank LIMIT _limit
    )

    SELECT jsonb_agg(entry ORDER BY rank) INTO result FROM combined_results;
    RETURN result;
END
$$
;