DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_relationship_between_accounts;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_relationship_between_accounts(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _account1_id INT;
  _account2_id INT;
  _observer_id INT;
  _debug BOOLEAN;
BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"account1": "string", "account2": "string", "observer": "string", "debug": "boolean"}', 4, NULL);

  _account1_id = 
    hivemind_postgrest_utilities.find_account_id(
      hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_argument_from_json(_params, 'account1', True),
        False),
    True);

  _account2_id = 
    hivemind_postgrest_utilities.find_account_id(
      hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_argument_from_json(_params, 'account2', True),
        False),
    True);

  _observer_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'observer', False),
      True),
    True);

  _debug = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'debug', False);

  RETURN jsonb_build_object(
      'follows', (SELECT EXISTS (SELECT 1 FROM hivemind_app.follows WHERE follower=_account1_id  AND FOLLOWING=_account2_id)),
      'ignores', (SELECT EXISTS (SELECT 1 FROM hivemind_app.muted WHERE follower=_account1_id  AND FOLLOWING=_account2_id)),
      'blacklists', (SELECT EXISTS (SELECT 1 FROM hivemind_app.blacklisted WHERE follower=_account1_id  AND FOLLOWING=_account2_id)),
      'follows_blacklists', (SELECT EXISTS (SELECT 1 FROM hivemind_app.follow_blacklisted WHERE follower=_account1_id  AND FOLLOWING=_account2_id)),
      'follows_muted', (SELECT EXISTS (SELECT 1 FROM hivemind_app.follow_muted WHERE follower=_account1_id  AND FOLLOWING=_account2_id))
  );
END
$$
;
