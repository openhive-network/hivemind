DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_account_posts_by_tag;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_account_posts_by_tag(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_account_id INT;
_observer_id INT;
_post_id INT;
_limit INT;
_muted_reasons_filter_mask INT;
_tag TEXT;

_account TEXT;
_permlink TEXT;

BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params,
                                                                 '{"account": "string", "tag": "string", "start_author": "string", "start_permlink": "string","limit": "number", "observer": "string", "muted_reasons_filter": "array"}',
                                                                 2,
                                                                 '{"start_permlink": "permlink must be string"}');

  _account = hivemind_postgrest_utilities.valid_account(
    hivemind_postgrest_utilities.parse_argument_from_json(_params, 'account', True),
    False);

  _account_id = hivemind_postgrest_utilities.find_account_id(_account, True);

  _tag = hivemind_postgrest_utilities.valid_tag(
    hivemind_postgrest_utilities.parse_argument_from_json(_params, 'tag', True),
    False);

  _permlink = hivemind_postgrest_utilities.valid_permlink(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start_permlink', False), True);

  _post_id = hivemind_postgrest_utilities.find_comment_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start_author', False), True),
    _permlink,
    True);

  _limit = hivemind_postgrest_utilities.valid_number(hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False),
                                                     least(20, hivemind_postgrest_utilities.get_max_posts_per_call_limit()),
                                                     1, hivemind_postgrest_utilities.get_max_posts_per_call_limit(), 'limit');

  _observer_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'observer', False), True),
    True);

  _muted_reasons_filter_mask := hivemind_postgrest_utilities.create_muted_reasons_bitmask(
    hivemind_postgrest_utilities.parse_integer_array_argument_from_json(_params, 'muted_reasons_filter', False)
  );

  RETURN hivemind_postgrest_utilities.get_account_posts_by_tag(_account_id, _tag, _post_id, _observer_id, _limit, _muted_reasons_filter_mask);
END
$$
;
