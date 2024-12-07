DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_followers;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_followers(IN _json_is_object BOOLEAN, IN _params JSONB, IN _called_from_condenser_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _start_id INT DEFAULT MAX_INT;
  _account_id INT;
  _state SMALLINT;
  _limit INT;
BEGIN
  _params = hivemind_postgrest_utilities.extract_parameters_for_get_following_and_followers(_json_is_object, _params, _called_from_condenser_api);
  _account_id = (_params->'account_id')::INT;
  _state = (_params->'hive_follows_state')::SMALLINT;
  _limit = (_params->'limit')::INT;

  IF (_params->'start_id')::INT <> 0 THEN
    _start_id = (
      SELECT hf.id
      FROM hivemind_app.hive_follows hf
      WHERE hf.following = (_params->'account_id')::INT AND hf.follower = (_params->'start_id')::INT
    );
  END IF;

  RETURN COALESCE(
  (
    SELECT jsonb_agg( -- condenser_api_get_followers
      jsonb_build_object(
        'following', _params->'account',
        'follower', row.name,
        'what', jsonb_build_array(_params->'follow_type')
      )
      ORDER BY row.id DESC
    ) 
    FROM (
      WITH followers AS MATERIALIZED
        (
        SELECT
          hf.id,
          hf.follower
        FROM hivemind_app.hive_follows hf
        WHERE hf.following = _account_id  AND hf.state = _state  -- hive_follows_following_state_id_idx
              AND hf.id < _start_id
        ORDER BY hf.id DESC
        LIMIT _limit
        )      
      SELECT
        followers.id,
        ha.name
      FROM followers
      JOIN hivemind_app.hive_accounts ha ON followers.follower = ha.id
      ORDER BY followers.id DESC
      LIMIT _limit
    ) row
  ),
  '[]'::jsonb
  );
END
$$
;

