DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_replies_by_last_update;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_replies_by_last_update(IN _params JSONB)
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
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"start_author": "string", "start_permlink": "string", "limit": "number", "truncate_body": "number", "observer": "string"}', 1, NULL);

  _author =
    hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start_author', True),
      False);

  _permlink =
    hivemind_postgrest_utilities.valid_permlink(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start_permlink', False),
    True);

  _author_id = hivemind_postgrest_utilities.find_account_id(_author, True);

  _limit =
    hivemind_postgrest_utilities.valid_number(
      hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False),
    20, 1, 100, 'limit');

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

  RETURN hivemind_postgrest_utilities.get_account_posts_by_replies(_author_id, _post_id, _observer_id, _limit, _truncate_body, (_permlink IS NOT NULL AND _permlink <> '' ), False);
END
$$
;