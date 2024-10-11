DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_relationship_between_accounts;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_relationship_between_accounts(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _account1 TEXT;
  _account2 TEXT;
  _observer TEXT;
  _debug BOOLEAN;
  _result JSONB;
  _state INT;
  _blacklisted BOOLEAN;
  _follow_blacklists BOOLEAN;
  _follow_muted BOOLEAN;
  _created_at TIMESTAMPTZ;
  _block_num INT;
BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"account1", "account2", "observer", "debug"}', '{"string", "string", "string", "boolean"}');

  _account1 = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'account1', 0, True);
  _account1 = hivemind_postgrest_utilities.valid_account(_account1);

  _account2 = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'account2', 1, True);
  _account2 = hivemind_postgrest_utilities.valid_account(_account2);

  _observer = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'observer', 2, False);
  PERFORM hivemind_postgrest_utilities.valid_account(_observer, True);

  _debug = hivemind_postgrest_utilities.parse_boolean_argument_from_json(_params, _json_is_object, 'debug', 3, False);

  SELECT state,
         COALESCE(blacklisted, FALSE),
         COALESCE(follow_blacklists, FALSE),
         COALESCE(follow_muted, FALSE),
         created_at,
         block_num
  INTO _state, _blacklisted, _follow_blacklists, _follow_muted, _created_at, _block_num
  FROM hivemind_app.bridge_get_relationship_between_accounts(_account1, _account2)
  LIMIT 1;

  _result := jsonb_build_object(
      'follows', CASE WHEN _state = 1 THEN TRUE ELSE FALSE END,
      'ignores', CASE WHEN _state = 2 THEN TRUE ELSE FALSE END,
      'blacklists', _blacklisted,
      'follows_blacklists', _follow_blacklists,
      'follows_muted', _follow_muted
  );

  IF _debug IS NOT NULL AND _debug THEN
      _result := _result || jsonb_build_object(
          'created_at', COALESCE(to_char(_created_at, 'YYYY-MM-DD"T"HH24:MI:SS'), NULL),
          'block_num', _block_num
      );
  END IF;

  RETURN _result;
END
$$
;