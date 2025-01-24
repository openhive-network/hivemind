DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_followers;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_followers(IN _params JSONB, IN _called_from_condenser_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _start_id INT DEFAULT 2147483647; --default to max allowed INT value to get the latest followers if _start_id is set to 0
  _account_id INT;
  _state SMALLINT;
  _limit INT;
BEGIN
  _params = hivemind_postgrest_utilities.extract_parameters_for_get_following_and_followers(_params, _called_from_condenser_api);
  _account_id = (_params->'account_id')::INT;
  _limit = (_params->'limit')::INT;

  IF (_params->'start_id')::INT <> 0 THEN
    IF (_params->'follows')::boolean THEN
      _start_id = (
        SELECT f.hive_rowid
        FROM hivemind_app.follows AS f
        WHERE f.following = _account_id
        AND f.follower = (_params->'start_id')::INT
      );
    ELSIF (_params->'mutes')::boolean THEN
      _start_id = (
        SELECT m.hive_rowid
        FROM hivemind_app.muted AS m
        WHERE m.following = _account_id
        AND m.follower = (_params->'start_id')::INT
      );
    END IF;
  END IF;

  RETURN COALESCE(
  (
    SELECT jsonb_agg( -- condenser_api_get_followers
      jsonb_build_object(
        'following', _params->'account',
        'follower', row.name,
        'what', jsonb_build_array(_params->'follow_type')
      )
      ORDER BY row.hive_rowid DESC
    )
    FROM (
      WITH followers AS MATERIALIZED
        (
        SELECT
          f.hive_rowid,
          f.follower
        FROM hivemind_app.follows AS f
        WHERE f.following = _account_id
              AND f.hive_rowid < _start_id
              AND (_params->'follows')::boolean
        UNION ALL
        SELECT
          m.hive_rowid,
          m.follower
        FROM hivemind_app.muted AS m
        WHERE m.following = _account_id
              AND m.hive_rowid < _start_id
              AND (_params->'mutes')::boolean
        ORDER BY hive_rowid DESC
        LIMIT _limit
        )
      SELECT
        followers.hive_rowid,
        ha.name
      FROM followers
      JOIN hivemind_app.hive_accounts AS ha ON followers.follower = ha.id
      ORDER BY followers.hive_rowid DESC
      LIMIT _limit
    ) row
  ),
  '[]'::jsonb
  );
END
$$
;

