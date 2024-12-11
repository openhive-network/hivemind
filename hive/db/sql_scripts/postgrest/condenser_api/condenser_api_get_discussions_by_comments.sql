DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_discussions_by_comments;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_discussions_by_comments(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_author TEXT;
_permlink TEXT;
_author_id INT;
_observer_id INT;
_post_id INT;
_limit INT;
_truncate_body INT;

BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"start_author": "string", "start_permlink": "string", "limit": "number", "truncate_body": "number", "filter_tags": "array", "observer": "string"}', 1, '{"start_permlink": "permlink must be string"}');

  IF hivemind_postgrest_utilities.parse_argument_from_json(_params, 'filter_tags', False) IS NOT NULL THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('filter_tags not supported');
  END IF;

  _author =
    hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start_author', True),
      False);

  _permlink =
    hivemind_postgrest_utilities.valid_permlink(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start_permlink', False),
    True);

  _author_id = hivemind_postgrest_utilities.find_account_id(_author, True);

  _limit = hivemind_postgrest_utilities.valid_number(hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False),
                                                     least(20, hivemind_postgrest_utilities.get_max_posts_per_call_limit()),
                                                     1, hivemind_postgrest_utilities.get_max_posts_per_call_limit(), 'limit');

  _truncate_body =
    hivemind_postgrest_utilities.valid_number(
      hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'truncate_body', False),
    0, 0, NULL, 'truncate_body');

  _observer_id =
    hivemind_postgrest_utilities.find_account_id(
      hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_argument_from_json(_params, 'observer', False), True),
    True);

  _post_id = hivemind_postgrest_utilities.find_comment_id( CASE WHEN _permlink IS NULL OR _permlink = '' THEN '' ELSE _author END, _permlink, True);

  RETURN hivemind_postgrest_utilities.get_account_posts_by_comments(_author_id, _post_id, _observer_id, _limit, _truncate_body, False);
END
$$
;
