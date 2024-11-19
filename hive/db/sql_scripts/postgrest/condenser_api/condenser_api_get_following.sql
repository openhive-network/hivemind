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
        WITH following_set AS
        (
          SELECT
            hf.id,
            hf.following
          FROM hivemind_app.hive_follows hf
          WHERE
            hf.state = (_params->'hive_follows_state')::SMALLINT
            AND hf.follower = (_params->'account_id')::INT
            AND NOT (_start_id <> 0 AND hf.id >= _start_id)
          ORDER BY
            -- + 1 is important hack for Postgres Intelligence to use dedicated index and avoid choosing PK index and performing a linear filtering on it
            hf.id + 1 DESC 
          LIMIT (_params->'limit')::INT
        )
        SELECT
          fs.id,
          ha.name
        FROM following_set fs
        JOIN hivemind_app.hive_accounts ha ON fs.following = ha.id
        ORDER BY fs.id DESC
      ) row
    ),
    '[]'::jsonb
    );
END
$$
;

