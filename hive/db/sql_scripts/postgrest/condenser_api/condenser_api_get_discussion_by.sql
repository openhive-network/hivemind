DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_discussions_by;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_discussions_by(IN _json_is_object BOOLEAN, IN _params JSONB, IN _case hivemind_postgrest_utilities.ranked_post_sort_type)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_tag TEXT;
_observer_id INT;
_post_id INT;
_limit INT;
_truncate_body INT;

BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"start_author","start_permlink","limit","tag","truncate_body","filter_tags","observer"}', '{"string","string","number","string","number","array","string"}', 0);
  IF hivemind_postgrest_utilities.parse_array_argument_from_json(_params, _json_is_object, 'filter_tags', 5, False) IS NOT NULL THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('filter_tags not supported');
  END IF;

  _limit =
    hivemind_postgrest_utilities.valid_number(
      hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'limit', 2, False),
    20, 1, 100, 'limit');

  _truncate_body =
    hivemind_postgrest_utilities.valid_number(
      hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'truncate_body', 4, False),
    0, NULL, NULL, 'truncate_body');

  _observer_id =
    hivemind_postgrest_utilities.find_account_id(
      hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'observer', 6, False), True),
    True);

  _tag = hivemind_postgrest_utilities.valid_tag(
    hivemind_postgrest_utilities.valid_tag(hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'tag', 3, False), True),
    True);

  _post_id =
    hivemind_postgrest_utilities.find_comment_id(
      hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'start_author', 0, False),
      True),
      hivemind_postgrest_utilities.valid_permlink(
        hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'start_permlink', 1, False),
      True),
    True);
  
  CASE
    WHEN _case = 'created' THEN
      IF _tag IS NULL OR _tag = '' THEN
        RETURN hivemind_postgrest_utilities.get_all_created_ranked_posts(_post_id, _observer_id, _limit, _truncate_body, False);
      ELSIF left(_tag, 5) = 'hive-' THEN
        RETURN hivemind_postgrest_utilities.get_ranked_posts_for_communities(_post_id, _observer_id, _limit, _truncate_body, _tag, False, 'created'::hivemind_postgrest_utilities.ranked_post_sort_type);
      ELSE
        RETURN hivemind_postgrest_utilities.get_created_ranked_posts_for_tag(_post_id, _observer_id, _limit, _truncate_body, _tag, False);
      END IF;
    WHEN _case = 'trending' THEN
      IF _tag IS NULL OR _tag = '' THEN
        RETURN hivemind_postgrest_utilities.get_all_trending_ranked_posts(_post_id, _observer_id, _limit, _truncate_body, False);
      ELSIF left(_tag, 5) = 'hive-' THEN
         RETURN hivemind_postgrest_utilities.get_ranked_posts_for_communities(_post_id, _observer_id, _limit, _truncate_body, _tag, False, 'trending'::hivemind_postgrest_utilities.ranked_post_sort_type);
      ELSE
        RETURN hivemind_postgrest_utilities.get_trending_ranked_posts_for_tag(_post_id, _observer_id, _limit, _truncate_body, _tag, False);
      END IF;
    WHEN _case = 'hot' THEN
      IF _tag IS NULL OR _tag = '' THEN
        RETURN hivemind_postgrest_utilities.get_all_hot_ranked_posts(_post_id, _observer_id, _limit, _truncate_body, False);
      ELSIF left(_tag, 5) = 'hive-' THEN
         RETURN hivemind_postgrest_utilities.get_ranked_posts_for_communities(_post_id, _observer_id, _limit, _truncate_body, _tag, False, 'hot'::hivemind_postgrest_utilities.ranked_post_sort_type);
      ELSE
        RETURN hivemind_postgrest_utilities.get_hot_ranked_posts_for_tag(_post_id, _observer_id, _limit, _truncate_body, _tag, False);
      END IF;
    WHEN _case = 'promoted' THEN
      IF _tag IS NULL OR _tag = '' THEN
        RETURN hivemind_postgrest_utilities.get_all_promoted_ranked_posts(_post_id, _observer_id, _limit, _truncate_body, False);
      ELSIF left(_tag, 5) = 'hive-' THEN
         RETURN hivemind_postgrest_utilities.get_ranked_posts_for_communities(_post_id, _observer_id, _limit, _truncate_body, _tag, False, 'promoted'::hivemind_postgrest_utilities.ranked_post_sort_type);
      ELSE
        RETURN hivemind_postgrest_utilities.get_promoted_ranked_posts_for_tag(_post_id, _observer_id, _limit, _truncate_body, _tag, False);
      END IF;
    WHEN _case = 'payout' THEN
      IF _tag IS NULL OR _tag = '' THEN
        RETURN hivemind_postgrest_utilities.get_all_payout_ranked_posts(_post_id, _observer_id, _limit, _truncate_body, False);
      ELSE
        RETURN hivemind_postgrest_utilities.get_payout_ranked_posts_for_tag(_post_id, _observer_id, _limit, _truncate_body, _tag, False);
      END IF;
    WHEN _case = 'payout_comments' THEN
      IF _tag IS NULL OR _tag = '' THEN
        RETURN hivemind_postgrest_utilities.get_all_payout_comments_ranked_posts(_post_id, _observer_id, _limit, _truncate_body, False);
      ELSE
        RETURN hivemind_postgrest_utilities.get_payout_comments_ranked_posts_for_tag(_post_id, _observer_id, _limit, _truncate_body, _tag, False);
      END IF;
  END CASE;
END
$$
;