DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_does_user_follow_any_lists;
CREATE FUNCTION hivemind_endpoints.bridge_api_does_user_follow_any_lists(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_observer_id INT;

BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"observer": "string"}', 1, NULL);

  _observer_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'observer', True), True),
    True);

  IF NOT EXISTS (SELECT ha.name FROM hivemind_app.hive_follows hf JOIN hivemind_app.hive_accounts ha ON ha.id = hf.following WHERE hf.follower = _observer_id AND hf.follow_blacklists LIMIT 1) THEN
    RETURN 'false'::jsonb;
  ELSE
    RETURN 'true'::jsonb;
  END IF;
END
$$
;