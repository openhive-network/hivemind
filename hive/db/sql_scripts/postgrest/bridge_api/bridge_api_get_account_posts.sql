DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_account_posts;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_account_posts(IN _params JSONB, IN _votes_mode SMALLINT DEFAULT 0)
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
_top_votes INT;
_truncate_body INT;

_account TEXT;
_permlink TEXT;

BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params,
                                                                 (CASE WHEN _votes_mode = 0 THEN '{"sort": "string", "account": "string", "start_author": "string", "start_permlink": "string","limit": "number", "observer": "string", "truncate_body": "number"}'
                                                                  ELSE '{"sort": "string", "account": "string", "start_author": "string", "start_permlink": "string","limit": "number", "observer": "string", "top_votes": "number", "truncate_body": "number"}' END)::JSON,
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

  _limit = hivemind_postgrest_utilities.valid_number(hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False),
                                                     least(20, hivemind_postgrest_utilities.get_max_posts_per_call_limit()),
                                                     1, hivemind_postgrest_utilities.get_max_posts_per_call_limit(), 'limit');

  _observer_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'observer', False), True),
    True);

  _top_votes = (CASE
    WHEN _votes_mode = 0 THEN 0
    ELSE hivemind_postgrest_utilities.valid_number(hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'top_votes', False), 0, 0, 10, 'top_votes')
  END);

  _truncate_body = hivemind_postgrest_utilities.valid_number(
    hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'truncate_body', False),
    0, 0, NULL, 'truncate_body');

  CASE hivemind_postgrest_utilities.parse_argument_from_json(_params, 'sort', True)
    WHEN 'blog' THEN RETURN hivemind_postgrest_utilities.get_account_posts_by_blog(_account, _account_id, _post_id, _observer_id, _limit, _truncate_body, True, _votes_mode, _top_votes);
    WHEN 'comments' THEN RETURN hivemind_postgrest_utilities.get_account_posts_by_comments(_account_id, _post_id, _observer_id, _limit, _truncate_body, True, _votes_mode, _top_votes);
    WHEN 'feed' THEN RETURN hivemind_postgrest_utilities.get_account_posts_by_feed(_account_id, _post_id, _observer_id, _limit, _truncate_body, True, _votes_mode, _top_votes);
    WHEN 'posts' THEN RETURN hivemind_postgrest_utilities.get_account_posts_by_posts(_account_id, _post_id, _observer_id, _limit, _truncate_body, _votes_mode, _top_votes);
    WHEN 'replies' THEN RETURN hivemind_postgrest_utilities.get_account_posts_by_replies(_account_id, _post_id, _observer_id, _limit, _truncate_body, (_permlink IS NOT NULL AND _permlink <> '' ), True, _votes_mode, _top_votes);
    WHEN 'payout' THEN RETURN hivemind_postgrest_utilities.get_account_posts_by_payout(_account_id, _post_id, _observer_id, _limit, _truncate_body, _votes_mode, _top_votes);
    ELSE RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Unsupported sort, valid sorts: blog, feed, posts, comments, replies, payout');
  END CASE;
END
$$
;
