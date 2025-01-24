DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_following;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_following(IN _params JSONB, IN _called_from_condenser_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_start_id INT DEFAULT 0;
BEGIN
  _params = hivemind_postgrest_utilities.extract_parameters_for_get_following_and_followers(_params, _called_from_condenser_api);

  IF (_params->'start_id')::INT <> 0 THEN
    IF (_params->'follows')::boolean THEN
      _start_id = (
        SELECT f.hive_rowid
        FROM hivemind_app.follows AS f
        WHERE f.follower = (_params->'account_id')::INT
        AND f.following = (_params->'start_id')::INT
      );
    ELSIF (_params->'mutes')::boolean THEN
      _start_id = (
        SELECT m.hive_rowid
        FROM hivemind_app.muted AS m
        WHERE m.follower = (_params->'account_id')::INT
        AND m.following = (_params->'start_id')::INT
      );
    END IF;
  END IF;

  RETURN COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'following', row.name,
          'follower', _params->>'account',
          'what', jsonb_build_array(_params->>'follow_type')
        )
        ORDER BY row.hive_rowid DESC
      ) FROM (
        WITH
        max_10k_follows AS
        (
          SELECT
            f.hive_rowid,
            f.following
          FROM hivemind_app.follows AS f
          WHERE
            f.follower = (_params->'account_id')::INT
          LIMIT 10000     -- if user follows more than 10K accounts, limit them
        ),
        max_10k_mutes AS
        (
          SELECT
            m.hive_rowid,
            m.following
          FROM hivemind_app.muted AS m
          WHERE
            m.follower = (_params->'account_id')::INT
          LIMIT 10000     -- if user ignores more than 10K accounts, limit them
        ),
        following_page AS -- condenser_api_get_following
        (
          SELECT
            f.hive_rowid,
            f.following
          FROM max_10k_follows AS f
          WHERE (_start_id = 0 OR f.hive_rowid < _start_id) AND (_params->'follows')::boolean
          UNION ALL
          SELECT
            m.hive_rowid,
            m.following
          FROM max_10k_mutes AS m
          WHERE (_start_id = 0 OR hive_rowid < _start_id) AND (_params->'mutes')::boolean
          ORDER BY hive_rowid DESC
          LIMIT (_params->'limit')::INT
        )
        SELECT
          fs.hive_rowid,
          ha.name
        FROM following_page fs
        JOIN hivemind_app.hive_accounts ha ON fs.following = ha.id
        ORDER BY fs.hive_rowid DESC
        LIMIT (_params->'limit')::INT
      ) row
    ),
    '[]'::jsonb
    );
END
$$
;

