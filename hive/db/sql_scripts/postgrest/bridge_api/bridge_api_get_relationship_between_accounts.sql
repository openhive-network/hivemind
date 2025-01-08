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

  IF _debug IS NULL THEN
    _debug = False;
  END IF;

  RETURN COALESCE(
    ( SELECT 
      CASE WHEN NOT _debug THEN 
        jsonb_build_object( -- bridge_api_get_relationship_between_accounts
          'follows', CASE WHEN row.state = 1 THEN TRUE ELSE FALSE END,
          'ignores', CASE WHEN row.state = 2 THEN TRUE ELSE FALSE END,
          'blacklists', row.blacklisted,
          'follows_blacklists', row.follow_blacklists,
          'follows_muted', row.follow_muted
      ) ELSE
        jsonb_build_object( -- bridge_api_get_relationship_between_accounts with debug
          'follows', CASE WHEN row.state = 1 THEN TRUE ELSE FALSE END,
          'ignores', CASE WHEN row.state = 2 THEN TRUE ELSE FALSE END,
          'blacklists', row.blacklisted,
          'follows_blacklists', row.follow_blacklists,
          'follows_muted', row.follow_muted,
          'created_at', COALESCE(to_char(row.created_at, 'YYYY-MM-DD"T"HH24:MI:SS'), NULL),
          'block_num', row.block_num
        )
      END
      FROM (
      SELECT
        hf.state,
        COALESCE(hf.blacklisted, False) AS blacklisted,
        COALESCE(hf.follow_blacklists, FALSE) AS follow_blacklists,
        COALESCE(hf.follow_muted, FALSE) AS follow_muted,
        hf.created_at,
        hf.block_num
      FROM
        hivemind_app.hive_follows hf
      WHERE
        hf.follower = _account1_id AND hf.following = _account2_id
      LIMIT 1
    ) row ),
      CASE WHEN NOT _debug THEN
        jsonb_build_object( -- bridge_api_get_relationship_between_accounts null
          'follows', FALSE,
          'ignores', FALSE,
          'blacklists', FALSE,
          'follows_blacklists', FALSE,
          'follows_muted', FALSE
      ) ELSE
        jsonb_build_object( -- bridge_api_get_relationship_between_accounts null with debug
          'follows', FALSE,
          'ignores', FALSE,
          'blacklists', FALSE,
          'follows_blacklists', FALSE,
          'follows_muted', FALSE,
          'created_at', NULL,
          'block_num', NULL
        )
      END
  );
END
$$
;