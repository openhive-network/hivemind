DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_account_posts;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_account_posts(IN _params JSONB)
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
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params,
                                                                 '{"sort": "string", "account": "string", "start_author": "string", "start_permlink": "string","limit": "number", "observer": "string"}',
                                                                 2,
                                                                 '{"start_permlink": "permlink must be string"}');

  _account = hivemind_postgrest_utilities.valid_account(
    hivemind_postgrest_utilities.parse_argument_from_json(_params, 'account', True),
    False);

  _account_id = hivemind_postgrest_utilities.find_account_id(_account, True);

  _permlink = hivemind_postgrest_utilities.valid_permlink(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start_permlink', False), True);

  _post_id = hivemind_postgrest_utilities.find_comment_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start_author', False), True),
    _permlink,
    True);

  _limit = hivemind_postgrest_utilities.valid_number(
    hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False),
    20, 1, 100, 'limit');
  
  _observer_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'observer', False), True),
    True);

  CASE hivemind_postgrest_utilities.parse_argument_from_json(_params, 'sort', True)
    WHEN 'blog' THEN RETURN hivemind_postgrest_utilities.get_account_posts_by_blog(_account, _account_id, _post_id, _observer_id, _limit, 0, True);
    WHEN 'comments' THEN RETURN hivemind_postgrest_utilities.get_account_posts_by_comments(_account_id, _post_id, _observer_id, _limit, 0, True);
    WHEN 'feed' THEN RETURN hivemind_postgrest_utilities.get_account_posts_by_feed(_account_id, _post_id, _observer_id, _limit, 0, True);
    WHEN 'posts' THEN RETURN hivemind_postgrest_utilities.get_account_posts_by_posts(_account_id, _post_id, _observer_id, _limit);
    WHEN 'replies' THEN RETURN hivemind_postgrest_utilities.get_account_posts_by_replies(_account_id, _post_id, _observer_id, _limit, 0, (_permlink IS NOT NULL AND _permlink <> '' ), True);
    WHEN 'payout' THEN RETURN hivemind_postgrest_utilities.get_account_posts_by_payout(_account_id, _post_id, _observer_id, _limit);
    ELSE RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Unsupported sort, valid sorts: blog, feed, posts, comments, replies, payout');
  END CASE;
END
$$
;