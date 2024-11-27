DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_ranked_posts;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_ranked_posts(IN _params JSONB)
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

BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"sort": "string", "start_author": "string", "start_permlink": "string", "limit": "number", "tag": "string", "observer": "string"}', 1, '{"start_permlink": "permlink must be string"}');

  _limit = hivemind_postgrest_utilities.valid_number(
    hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False),
    20, 1, 100, 'limit');

  _post_id = hivemind_postgrest_utilities.find_comment_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start_author', False), True),
    hivemind_postgrest_utilities.valid_permlink(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start_permlink', False), True),
    True);

  _tag = hivemind_postgrest_utilities.valid_tag(
    hivemind_postgrest_utilities.valid_tag(hivemind_postgrest_utilities.parse_argument_from_json(_params, 'tag', False), True),
    True);

  _observer_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'observer', False),
      /* allow_empty */ (CASE WHEN _tag = 'my' THEN False ELSE True END)),
    True);

  CASE hivemind_postgrest_utilities.parse_argument_from_json(_params, 'sort', True)
    WHEN 'trending' THEN _sort_type = 'trending';
    WHEN 'hot' THEN _sort_type = 'hot';
    WHEN 'created' THEN _sort_type = 'created';
    WHEN 'promoted' THEN _sort_type = 'promoted';
    WHEN 'payout' THEN _sort_type = 'payout';
    WHEN 'payout_comments' THEN _sort_type = 'payout_comments';
    WHEN 'muted' THEN _sort_type = 'muted';
    ELSE RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Unsupported sort, valid sorts: trending, hot, created, promoted, payout, payout_comments, muted');
  END CASE;

  IF _tag IS NULL OR _tag = '' OR _tag = 'all' THEN
    CASE _sort_type
      WHEN 'trending' THEN RETURN hivemind_postgrest_utilities.get_all_trending_ranked_posts(_post_id, _observer_id, _limit, 0, True);
      WHEN 'hot' THEN RETURN hivemind_postgrest_utilities.get_all_hot_ranked_posts(_post_id, _observer_id, _limit, 0, True);
      WHEN 'created' THEN RETURN hivemind_postgrest_utilities.get_all_created_ranked_posts(_post_id, _observer_id, _limit, 0, True);
      WHEN 'promoted' THEN RETURN hivemind_postgrest_utilities.get_all_promoted_ranked_posts(_post_id, _observer_id, _limit, 0, True);
      WHEN 'payout' THEN RETURN hivemind_postgrest_utilities.get_all_payout_ranked_posts(_post_id, _observer_id, _limit, 0, True);
      WHEN 'payout_comments' THEN RETURN hivemind_postgrest_utilities.get_all_payout_comments_ranked_posts(_post_id, _observer_id, _limit, 0, True);
      WHEN 'muted' THEN RETURN hivemind_postgrest_utilities.get_all_muted_ranked_posts(_post_id, _observer_id, _limit);
    END CASE;
  ELSIF _tag = 'my' THEN
    CASE _sort_type
      WHEN 'trending' THEN RETURN hivemind_postgrest_utilities.get_trending_ranked_posts_for_observer_communities(_post_id, _observer_id, _limit);
      WHEN 'hot' THEN RETURN hivemind_postgrest_utilities.get_hot_ranked_posts_for_observer_communities(_post_id, _observer_id, _limit);
      WHEN 'created' THEN RETURN hivemind_postgrest_utilities.get_created_ranked_posts_for_observer_communities(_post_id, _observer_id, _limit);
      WHEN 'promoted' THEN RETURN hivemind_postgrest_utilities.get_promoted_ranked_posts_for_observer_communities(_post_id, _observer_id, _limit);
      WHEN 'payout' THEN RETURN hivemind_postgrest_utilities.get_payout_ranked_posts_for_observer_communities(_post_id, _observer_id, _limit);
      WHEN 'payout_comments' THEN RETURN hivemind_postgrest_utilities.get_payout_comments_ranked_posts_for_observer_communities(_post_id, _observer_id, _limit);
      WHEN 'muted' THEN RETURN hivemind_postgrest_utilities.get_muted_ranked_posts_for_observer_communities(_post_id, _observer_id, _limit);
    END CASE;
  ELSIF hivemind_postgrest_utilities.check_community(_tag) THEN
    RETURN hivemind_postgrest_utilities.get_ranked_posts_for_communities(_post_id, _observer_id, _limit, 0, _tag, True, _sort_type);
  ELSE
    CASE _sort_type
      WHEN 'trending' THEN RETURN hivemind_postgrest_utilities.get_trending_ranked_posts_for_tag(_post_id, _observer_id, _limit, 0, _tag, True);
      WHEN 'hot' THEN RETURN hivemind_postgrest_utilities.get_hot_ranked_posts_for_tag(_post_id, _observer_id, _limit, 0, _tag, True);
      WHEN 'created' THEN RETURN hivemind_postgrest_utilities.get_created_ranked_posts_for_tag(_post_id, _observer_id, _limit, 0, _tag, True);
      WHEN 'promoted' THEN RETURN hivemind_postgrest_utilities.get_promoted_ranked_posts_for_tag(_post_id, _observer_id, _limit, 0, _tag, True);
      WHEN 'payout' THEN RETURN hivemind_postgrest_utilities.get_payout_ranked_posts_for_tag(_post_id, _observer_id, _limit, 0, _tag, True);
      WHEN 'payout_comments' THEN RETURN hivemind_postgrest_utilities.get_payout_comments_ranked_posts_for_tag(_post_id, _observer_id, _limit, 0, _tag, True);
      WHEN 'muted' THEN RETURN hivemind_postgrest_utilities.get_muted_ranked_posts_for_tag(_post_id, _observer_id, _limit, _tag);
    END CASE;
  END IF;
END
$$
;