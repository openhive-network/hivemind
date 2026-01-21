DROP FUNCTION IF EXISTS hivemind_endpoints.hive_api_get_reblogged_by_account;
CREATE FUNCTION hivemind_endpoints.hive_api_get_reblogged_by_account(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_limit INT;
_tag TEXT;
_post_id INT;
_observer_id INT;
_sort_type hivemind_postgrest_utilities.ranked_post_sort_type;
_community_id INT;
_tag_id INT;
_result JSONB;

BEGIN
  -- Validate parameters (same as bridge.get_ranked_posts)
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"sort": "string", "start_author": "string", "start_permlink": "string", "limit": "number", "tag": "string", "observer": "string"}', 1, '{"start_permlink": "permlink must be string"}');

  _limit = hivemind_postgrest_utilities.valid_number(hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False),
                                                     least(20, hivemind_postgrest_utilities.get_max_posts_per_call_limit()),
                                                     1, hivemind_postgrest_utilities.get_max_posts_per_call_limit(), 'limit');

  _post_id = hivemind_postgrest_utilities.find_comment_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start_author', False), True),
    hivemind_postgrest_utilities.valid_permlink(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start_permlink', False), True),
    True);

  _tag = hivemind_postgrest_utilities.valid_tag(
    hivemind_postgrest_utilities.valid_tag(hivemind_postgrest_utilities.parse_argument_from_json(_params, 'tag', False), True),
    True);

  -- Observer is required for this endpoint
  _observer_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'observer', True),
      False),
    True);

  IF _observer_id = 0 THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('observer is required for this endpoint');
  END IF;

  CASE hivemind_postgrest_utilities.parse_argument_from_json(_params, 'sort', True)
    WHEN 'trending' THEN _sort_type = 'trending';
    WHEN 'hot' THEN _sort_type = 'hot';
    WHEN 'created' THEN _sort_type = 'created';
    WHEN 'payout' THEN _sort_type = 'payout';
    WHEN 'payout_comments' THEN _sort_type = 'payout_comments';
    WHEN 'muted' THEN _sort_type = 'muted';
    ELSE RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Unsupported sort, valid sorts: trending, hot, created, payout, payout_comments, muted');
  END CASE;

  -- Get reblog status for posts matching the criteria
  IF _tag IS NULL OR _tag = '' OR _tag = 'all' THEN
    _result = hivemind_postgrest_utilities.get_reblogged_posts_for_all(_post_id, _observer_id, _limit, _sort_type);
  ELSIF _tag = 'my' THEN
    _result = hivemind_postgrest_utilities.get_reblogged_posts_for_observer_communities(_post_id, _observer_id, _limit, _sort_type);
  ELSIF hivemind_postgrest_utilities.check_community(_tag) THEN
    _result = hivemind_postgrest_utilities.get_reblogged_posts_for_community(_post_id, _observer_id, _limit, _tag, _sort_type);
  ELSE
    _result = hivemind_postgrest_utilities.get_reblogged_posts_for_tag(_post_id, _observer_id, _limit, _tag, _sort_type);
  END IF;

  RETURN _result;
END
$$
;
