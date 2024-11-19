DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_following_or_followers;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_following_or_followers(IN _json_is_object BOOLEAN, IN _params JSONB, IN _get_following BOOLEAN, IN _called_from_condenser_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _account TEXT;
  _account_id INT;
  _start_id INT;
  _limit INT;
  _follow_type TEXT;
BEGIN
  -- this method can be called from follow api or condenser api and they diffs with one argument name: 'follow_type' in condenser and 'type' in follow
  IF _called_from_condenser_api THEN
    PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"account","start","follow_type","limit"}', '{"string","string","string","number"}', 1);
  ELSE
    PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"account","start","type","limit"}', '{"string","string","string","number"}', 1);
  END IF;

  _account =
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'account', 0, True),
    False);

  _account_id = hivemind_postgrest_utilities.find_account_id(_account, True);

  _start_id =
    hivemind_postgrest_utilities.find_account_id(
      hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'start', 1, False),
        True),
      True);

  IF _called_from_condenser_api THEN
    _follow_type = COALESCE(hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'follow_type', 2, False), 'blog');
  ELSE
    _follow_type = COALESCE(hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'type', 2, False), 'blog');
  END IF;

  IF _follow_type NOT IN ('blog', 'ignore') THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Unsupported follow type, valid types: blog, ignore');
  END IF;

  _limit =
    hivemind_postgrest_utilities.valid_number(
      hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'limit', 3, False),
    1000, 1, 1000, 'limit');

  IF _start_id <> 0 THEN
    _start_id = (
      SELECT hf.id
      FROM hivemind_app.hive_follows hf
      WHERE
      (
        CASE
          WHEN _get_following THEN (hf.follower = _account_id AND hf.following = _start_id)
          ELSE (hf.following = _account_id AND hf.follower = _start_id)
        END
      )
    );
  END IF;

  IF _get_following THEN
    RETURN COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'following', row.name,
          'follower', _account,
          'what', jsonb_build_array(_follow_type)
        )
      ) FROM (
        WITH following_set AS
        (
          SELECT
            hf.id,
            hf.following
          FROM hivemind_app.hive_follows hf
          WHERE
            ( CASE WHEN _follow_type = 'blog' THEN hf.state = 1 ELSE hf.state = 2 END )
            AND hf.follower = _account_id
            AND NOT (_start_id <> 0 AND hf.id >= _start_id)
          ORDER BY
            hf.id + 1 DESC
          LIMIT _limit
        )
        SELECT
          ha.name
        FROM following_set fs
        JOIN hivemind_app.hive_accounts ha ON fs.following = ha.id
        ORDER BY fs.id DESC
      ) row
    ),
    '[]'::jsonb
    );
  END IF;

  RETURN COALESCE(
  (
    SELECT jsonb_agg(
      jsonb_build_object(
        'following', _account,
        'follower', row.name,
        'what', jsonb_build_array(_follow_type)
      )
    ) FROM (
      SELECT
        ha.name
      FROM hivemind_app.hive_follows hf
      JOIN hivemind_app.hive_accounts ha ON hf.follower = ha.id
      WHERE
        ( CASE WHEN _follow_type = 'blog' THEN hf.state = 1 ELSE hf.state = 2 END )
        AND hf.following = _account_id
        AND NOT (_start_id <> 0 AND hf.id >= _start_id )
      ORDER BY hf.id DESC
      LIMIT _limit
    ) row
  ),
  '[]'::jsonb
  );
END
$$
;

