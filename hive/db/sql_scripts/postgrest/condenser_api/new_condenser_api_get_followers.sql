DROP FUNCTION IF EXISTS hivemind_endpoints.new_condenser_api_get_followers;
CREATE FUNCTION hivemind_endpoints.new_condenser_api_get_followers(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _account TEXT;
  _account_id INT;
  _start TEXT;
  _start_id INT;
  _follow_type TEXT;
  _limit INT;
  _result JSONB;
BEGIN
  _params := hivemind_postgrest_utilities.validate_json_arguments( _params, '{"account": "string", "start" : "string", "type" : "string", "limit" : "number"}',  4,   NULL  );

  _account := _params->'account';
  _account_id := hivemind_postgrest_utilities.find_account_id( _account, TRUE );
  if (_account_id = 0) then
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Invalid account');
  end if;

  _start := _params->'start';
  _start_id := hivemind_postgrest_utilities.find_account_id( _start, TRUE );
  if (_start_id = 0) then
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Invalid start account');
  end if;

  _follow_type := hivemind_postgrest_utilities.parse_argument_from_json(_params, 'type', FALSE);
  _limit = (_params->'limit')::INT;

  IF _follow_type = 'blog' THEN
    _result := (
      SELECT jsonb_agg(
        jsonb_build_object(
          'following', _account,
          'follower', ha.name,
          'what', '[blog]',
        )
      )
      FROM {SCHEMA_NAME}.follows f
      JOIN {SCHEMA_NAME}.hive_accounts ha ON ha.id = f.follower
      WHERE f.following = _account_id AND ha.id < _start_id
      ORDER BY f.follower DESC
      LIMIT _limit
    );
ELSIF _follow_type = 'ignore' THEN
    _result := (
      SELECT jsonb_agg(
        jsonb_build_object(
          'following', _account,
          'follower', ha.name,
          'what', '[ignore]',
        )
      )
      FROM {SCHEMA_NAME}.muted m
      JOIN {SCHEMA_NAME}.hive_accounts ha ON ha.id = m.follower
      WHERE m.following = _account_id AND ha.id < _start_id
      ORDER BY m.follower DESC
      LIMIT _limit
    );
  ELSE
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Unsupported follow_type, valid values: blog, ignore');
  END IF;

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;
