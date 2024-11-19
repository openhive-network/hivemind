DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.extract_parameters_for_get_following_and_followers;
CREATE FUNCTION hivemind_postgrest_utilities.extract_parameters_for_get_following_and_followers(IN _json_is_object BOOLEAN, IN _params JSONB, IN _called_from_condenser_api BOOLEAN)
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
  _hive_follows_state INT;
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

  IF _follow_type = 'blog' THEN
    _hive_follows_state = 1;
  ELSIF _follow_type = 'ignore' THEN
    _hive_follows_state = 2;
  ELSE
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Unsupported follow type, valid types: blog, ignore');
  END IF;

  _limit =
    hivemind_postgrest_utilities.valid_number(
      hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'limit', 3, False),
    1000, 1, 1000, 'limit');

  RETURN jsonb_build_object(
    'account', _account,
    'account_id', _account_id,
    'start_id', _start_id,
    'limit', _limit,
    'follow_type', _follow_type,
    'hive_follows_state', _hive_follows_state
  );
END
$$
;