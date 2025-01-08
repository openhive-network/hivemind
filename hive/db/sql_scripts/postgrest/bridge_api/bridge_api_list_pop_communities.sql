DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_list_pop_communities;
CREATE FUNCTION hivemind_endpoints.bridge_api_list_pop_communities(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
    _limit INTEGER;
    _head_block_time TIMESTAMP;
BEGIN
    _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"limit": "number"}', 0, NULL);

    _limit := hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False);
    _limit := hivemind_postgrest_utilities.valid_number(_limit, 25, 1, 25, 'limit');

    _head_block_time := hivemind_app.head_block_time();

    RETURN (
      SELECT
        jsonb_agg( jsonb_build_array(name, title) ORDER BY newsubs DESC, id DESC)
      FROM
      (
        SELECT
          hc.id,
          hc.name,
          hc.title,
          stats.newsubs
        FROM hivemind_app.hive_communities hc
        JOIN (
          SELECT
            community_id,
            COUNT(*) newsubs
          FROM hivemind_app.hive_subscriptions
          WHERE created_at > _head_block_time - INTERVAL '1 MONTH'
          GROUP BY community_id
        ) stats ON stats.community_id = hc.id
        ORDER BY stats.newsubs DESC, hc.id DESC
        LIMIT _limit
      )
    );
END
$$
;