DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.extract_parameters_for_get_following_and_followers;
CREATE FUNCTION hivemind_postgrest_utilities.extract_parameters_for_get_following_and_followers(IN _params JSONB, IN _called_from_condenser_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _account TEXT;
  _account_id INT;
  _start TEXT;
  _limit INT;
  _follow_type TEXT;
  _hive_follows_state INT;
BEGIN
  -- this method can be called from follow api or condenser api and they diffs with one argument name: 'follow_type' in condenser and 'type' in follow
  IF _called_from_condenser_api THEN
    _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"account": "string", "start": "string", "follow_type": "string", "limit": "number"}', 1, NULL);
  ELSE
    _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"account": "string", "start": "string", "type": "string", "limit": "number"}', 1, NULL);
  END IF;

  _account =
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'account', True),
    False);

  _account_id = hivemind_postgrest_utilities.find_account_id(_account, True);

  _start =
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start', False),
      True);
  PERFORM hivemind_postgrest_utilities.find_account_id(_start, True); -- make sure account exists

  IF _called_from_condenser_api THEN
    _follow_type = COALESCE(hivemind_postgrest_utilities.parse_argument_from_json(_params, 'follow_type', False), 'blog');
  ELSE
    _follow_type = COALESCE(hivemind_postgrest_utilities.parse_argument_from_json(_params, 'type', False), 'blog');
  END IF;

  IF _follow_type NOT IN ('blog', 'ignore') THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Unsupported follow type, valid types: blog, ignore');
  END IF;

  _limit =
    hivemind_postgrest_utilities.valid_number(
      hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False),
    1000, 1, 1000, 'limit');

  RETURN jsonb_build_object(
    'account', _account,
    'account_id', _account_id,
    'start', COALESCE(_start, ''),
    'limit', _limit,
    'follow_type', _follow_type,
    'follows', _follow_type = 'blog',
    'mutes', _follow_type = 'ignore'
  );
END
$$
;
