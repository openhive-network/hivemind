DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_following;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_following(IN _params JSONB, IN _called_from_condenser_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_start TEXT DEFAULT '';
BEGIN
  _params = hivemind_postgrest_utilities.extract_parameters_for_get_following_and_followers(_params, _called_from_condenser_api);
  _start = (_params->>'start')::TEXT;

  RETURN COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'following', row.name,
          'follower', _params->>'account',
          'what', jsonb_build_array(_params->>'follow_type')
        )
        ORDER BY row.name
      ) FROM (
        WITH
        max_10k_follows AS
        (
          SELECT
            f.following
          FROM hivemind_app.follows AS f
          WHERE
            f.follower = (_params->'account_id')::INT
          LIMIT 10000     -- if user follows more than 10K accounts, limit them
        ),
        max_10k_mutes AS
        (
          SELECT
            m.following
          FROM hivemind_app.muted AS m
          WHERE
            m.follower = (_params->'account_id')::INT
          LIMIT 10000     -- if user ignores more than 10K accounts, limit them
        ),
        following_page AS -- condenser_api_get_following
        (
          SELECT ha.name
          FROM max_10k_follows AS f
          JOIN hivemind_app.hive_accounts AS ha ON f.following = ha.id
          WHERE (_start = '' OR ha.name > _start) AND (_params->'follows')::boolean
          UNION ALL
          SELECT ha.name
          FROM max_10k_mutes AS m
          JOIN hivemind_app.hive_accounts AS ha ON m.following = ha.id
          WHERE (_start = '' OR ha.name > _start) AND (_params->'mutes')::boolean
          ORDER BY name
          LIMIT (_params->'limit')::INT
        )
        SELECT name
        FROM following_page fs
        ORDER BY name
        LIMIT (_params->'limit')::INT
      ) row
    ),
    '[]'::jsonb
    );
END
$$
;

