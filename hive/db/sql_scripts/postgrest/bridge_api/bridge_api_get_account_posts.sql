DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_account_posts;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_account_posts(IN _json_is_object BOOLEAN, IN _params JSONB)
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

_account TEXT;
_permlink TEXT;

BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"sort","account","start_author","start_permlink","limit","observer"}', '{"string","string","string","string","number","string"}', 2);

  _account = hivemind_postgrest_utilities.valid_account(
    hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'account', 1, True),
    False);

  _account_id = hivemind_postgrest_utilities.find_account_id(_account, True);

  _permlink = hivemind_postgrest_utilities.valid_permlink(
      hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'start_permlink', 3, False), True);

  _post_id = hivemind_postgrest_utilities.find_comment_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'start_author', 2, False), True),
    _permlink,
    True);

  _limit = hivemind_postgrest_utilities.valid_number(
    hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'limit', 4, False),
    20, 1, 100, 'limit');
  
  _observer_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'observer', 5, False), True),
    True);

  CASE hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'sort', 0, True)
    WHEN 'blog' THEN RETURN hivemind_postgrest_utilities.get_account_posts_by_blog(_account, _account_id, _post_id, _observer_id, _limit, 0, True);
    WHEN 'comments' THEN RETURN hivemind_postgrest_utilities.get_account_posts_by_comments(_account_id, _post_id, _observer_id, _limit, 0, True);
    WHEN 'feed' THEN RETURN hivemind_postgrest_utilities.get_account_posts_by_feed(_account_id, _post_id, _observer_id, _limit);
    WHEN 'posts' THEN RETURN hivemind_postgrest_utilities.get_account_posts_by_posts(_account_id, _post_id, _observer_id, _limit);
    WHEN 'replies' THEN RETURN hivemind_postgrest_utilities.get_account_posts_by_replies(_account_id, _post_id, _observer_id, _limit, 0, (_permlink IS NOT NULL AND _permlink <> '' ), True);
    WHEN 'payout' THEN RETURN hivemind_postgrest_utilities.get_account_posts_by_payout(_account_id, _post_id, _observer_id, _limit);
    ELSE RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Unsupported sort, valid sorts: blog, feed, posts, comments, replies, payout');
  END CASE;
END
$$
;