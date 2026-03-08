DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_for_you_feed;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_for_you_feed(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_account TEXT;
_account_id INT;
_limit INT;
_post_id INT;
_observer TEXT;
_observer_id INT;
BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(
    _params,
    '{"account": "string", "limit": "number", "start_author": "string", "start_permlink": "string", "observer": "string"}',
    1,
    '{"start_permlink": "permlink must be string"}'
  );

  _account = hivemind_postgrest_utilities.valid_account(
    hivemind_postgrest_utilities.parse_argument_from_json(_params, 'account', True),
    False
  );

  _account_id = hivemind_postgrest_utilities.find_account_id(_account, False);

  _limit = hivemind_postgrest_utilities.valid_number(
    hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False),
    20, 1, 200, 'limit'
  );

  _post_id = hivemind_postgrest_utilities.find_comment_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start_author', False), True),
    hivemind_postgrest_utilities.valid_permlink(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start_permlink', False), True),
    True
  );

  _observer = hivemind_postgrest_utilities.valid_account(
    hivemind_postgrest_utilities.parse_argument_from_json(_params, 'observer', False),
    True
  );

  IF _observer IS NOT NULL AND _observer != '' THEN
    _observer_id = hivemind_postgrest_utilities.find_account_id(_observer, True);
  ELSE
    _observer_id = _account_id;
  END IF;

  RETURN hivemind_postgrest_utilities.get_for_you_feed(_account_id, _post_id, _observer_id, _limit);
END
$$
;
