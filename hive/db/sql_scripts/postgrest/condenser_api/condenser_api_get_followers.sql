DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_followers;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_followers(IN _params JSONB, IN _called_from_condenser_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _start TEXT DEFAULT '';
  _account_id INT;
  _state SMALLINT;
  _limit INT;
BEGIN
  _params = hivemind_postgrest_utilities.extract_parameters_for_get_following_and_followers(_params, _called_from_condenser_api);
  _account_id = (_params->'account_id')::INT;
  _limit = (_params->'limit')::INT;
  _start = (_params->>'start')::TEXT;

  RETURN COALESCE(
  (
    SELECT jsonb_agg( -- condenser_api_get_followers
      jsonb_build_object(
        'following', _params->'account',
        'follower', row.name,
        'what', jsonb_build_array(_params->'follow_type')
      )
      ORDER BY row.name
    )
    FROM (
      WITH followers AS MATERIALIZED
        (
        SELECT ha.name
        FROM hivemind_app.follows AS f
        JOIN hivemind_app.hive_accounts AS ha ON f.follower = ha.id
        WHERE f.following = _account_id
              AND (_start = '' OR ha.name > _start)
              AND (_params->'follows')::boolean
        UNION ALL
        SELECT ha.name
        FROM hivemind_app.muted AS m
        JOIN hivemind_app.hive_accounts AS ha ON m.follower = ha.id
        WHERE m.following = _account_id
              AND (_start = '' OR ha.name > _start)
              AND (_params->'mutes')::boolean
        ORDER BY name
        LIMIT _limit
        )
      SELECT name
      FROM followers
      ORDER BY name
      LIMIT _limit
    ) row
  ),
  '[]'::jsonb
  );
END
$$
;

