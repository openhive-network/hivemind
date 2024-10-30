DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_does_user_follow_any_lists;
CREATE FUNCTION hivemind_endpoints.bridge_api_does_user_follow_any_lists(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_observer_id INT;

BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"observer"}', '{"string"}');

  _observer_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'observer', 0, True), True),
    True);

  IF NOT EXISTS (SELECT ha.name FROM hivemind_app.hive_follows hf JOIN hivemind_app.hive_accounts ha ON ha.id = hf.following WHERE hf.follower = _observer_id AND hf.follow_blacklists LIMIT 1) THEN
    RETURN 'false'::jsonb;
  ELSE
    RETURN 'true'::jsonb;
  END IF;
END
$$
;