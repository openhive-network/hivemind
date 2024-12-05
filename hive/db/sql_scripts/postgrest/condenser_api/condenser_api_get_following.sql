DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_following;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_following(IN _json_is_object BOOLEAN, IN _params JSONB, IN _called_from_condenser_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_start_id INT DEFAULT 0;
BEGIN
  _params = hivemind_postgrest_utilities.extract_parameters_for_get_following_and_followers(_json_is_object, _params, _called_from_condenser_api);

  IF (_params->'start_id')::INT <> 0 THEN
    _start_id = (
      SELECT hf.id
      FROM hivemind_app.hive_follows hf
      WHERE hf.follower = (_params->'account_id')::INT AND hf.following = (_params->'start_id')::INT
    );
  END IF;

  RETURN COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'following', row.name,
          'follower', _params->>'account',
          'what', jsonb_build_array(_params->>'follow_type')
        )
        ORDER BY row.id DESC
      ) FROM (
        WITH 
        max_10k_following AS
        (
          SELECT
            hf.id,
            hf.following
          FROM hivemind_app.hive_follows hf
          WHERE -- INDEX ONLY SCAN of hive_follows_follower_following_state_idx
            hf.state = (_params->'hive_follows_state')::SMALLINT
            AND hf.follower = (_params->'account_id')::INT
          LIMIT 10000     -- if user follows more than 10K accounts, limit them
        ),        
        following_page AS -- condenser_api_get_following
        (
          SELECT
            hf.id,
            hf.following
          FROM max_10k_following hf
          WHERE
            (_start_id = 0 OR hf.id < _start_id)
          ORDER BY hf.id DESC 
          LIMIT (_params->'limit')::INT
        )
        SELECT
          fs.id,
          ha.name
        FROM following_page fs
        JOIN hivemind_app.hive_accounts ha ON fs.following = ha.id
        ORDER BY fs.id DESC
        LIMIT (_params->'limit')::INT
      ) row
    ),
    '[]'::jsonb
    );
END
$$
;

