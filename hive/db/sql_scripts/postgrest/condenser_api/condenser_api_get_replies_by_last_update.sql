DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_replies_by_last_update;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_replies_by_last_update(IN _json_is_object BOOLEAN, IN _params JSONB)
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
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"start_author","start_permlink","limit","truncate_body","observer"}', '{"string","string","number","number","string"}', 1);

  _author =
    hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'start_author', 0, True),
      False);

  _permlink =
    hivemind_postgrest_utilities.valid_permlink(
      hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'start_permlink', 1, False),
    True);

  _author_id = hivemind_postgrest_utilities.find_account_id(_author, True);

  _limit =
    hivemind_postgrest_utilities.valid_number(
      hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'limit', 2, False),
    20, 1, 100, 'limit');

  _truncate_body =
    hivemind_postgrest_utilities.valid_number(
      hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'truncate_body', 3, False),
    0, 0, NULL, 'truncate_body');

  _observer_id =
    hivemind_postgrest_utilities.find_account_id(
      hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'observer', 4, False), True),
    True);

  _post_id = hivemind_postgrest_utilities.find_comment_id( CASE WHEN _permlink IS NULL OR _permlink = '' THEN '' ELSE _author END, _permlink, True);

  RETURN hivemind_postgrest_utilities.get_account_posts_by_replies(_author_id, _post_id, _observer_id, _limit, _truncate_body, (_permlink IS NOT NULL AND _permlink <> '' ), False);
END
$$
;