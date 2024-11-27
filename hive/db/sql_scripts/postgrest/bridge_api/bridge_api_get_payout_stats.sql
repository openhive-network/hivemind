DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_payout_stats;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_payout_stats(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
    _limit INTEGER;
    _result JSONB;
    _total FLOAT;
    _blog_ttl FLOAT;
BEGIN
    _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"limit": "number"}', 0, NULL);
    _limit = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False);
    _limit = hivemind_postgrest_utilities.valid_number(_limit, 250, 1, 250, 'limit');

    SELECT jsonb_agg(item)
    INTO _result
    FROM (
        SELECT jsonb_build_array(  -- bridge_api_get_payout_stats
                COALESCE(hc.name, '@' || hpv.author),
                COALESCE(hc.title, COALESCE('@' || hpv.author, 'Unknown')),
                hpv.payout::float,
                hpv.posts,
                hpv.authors
            ) AS item
        FROM
            hivemind_app.payout_stats_view hpv
        LEFT JOIN
            hivemind_app.hive_communities hc ON hc.id = hpv.community_id
        WHERE
            (hpv.community_id IS NULL AND hpv.author IS NOT NULL)
            OR (hpv.community_id IS NOT NULL AND hpv.author IS NULL)
        ORDER BY
            hpv.payout DESC
        LIMIT _limit
    ) AS subquery;

    SELECT
        COALESCE(SUM(CASE WHEN author IS NULL THEN payout END), 0.0) AS _total,
        COALESCE(SUM(CASE WHEN community_id IS NULL AND author IS NULL THEN payout END), 0.0) AS _blog_ttl
    INTO
        _total,
        _blog_ttl
    FROM
        hivemind_app.payout_stats_view;

    RETURN jsonb_build_object(
        'items', _result,
        'total', _total,
        'blogs', _blog_ttl
    );
END
$$;