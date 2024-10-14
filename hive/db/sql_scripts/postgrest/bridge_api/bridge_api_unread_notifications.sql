DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_unread_notifications;
CREATE FUNCTION hivemind_endpoints.bridge_api_unread_notifications(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _account TEXT;
  _min_score SMALLINT := 25;
  _lastread_at TIMESTAMP WITHOUT TIME ZONE;
  _unread BIGINT;
BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"account", "min_score"}', '{"string", "number"}');

  _account = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'account', 0, True);
  _account = hivemind_postgrest_utilities.valid_account(_account);

  _min_score = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'min_score', 1, False);
  _min_score = hivemind_postgrest_utilities.valid_number(_min_score, 25, 0, 100, 'score');

  SELECT lastread_at, unread INTO _lastread_at, _unread FROM hivemind_app.get_number_of_unread_notifications( _account, _min_score);

  RETURN jsonb_build_object(
    'lastread', to_char(_lastread_at, 'YYYY-MM-DD HH24:MI:SS'),
    'unread', _unread
    );
END
$$
;