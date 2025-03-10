DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_condenser_api_method;
CREATE FUNCTION hivemind_postgrest_utilities.get_condenser_api_method(IN __method_type TEXT, IN __params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  result JSONB;
BEGIN
  CASE
    WHEN __method_type = 'get_follow_count' THEN
      result :=  hivemind_endpoints.condenser_api_get_follow_count(__params);
    WHEN __method_type = 'get_reblogged_by' THEN
      result :=  hivemind_endpoints.condenser_api_get_reblogged_by(__params);
    WHEN __method_type = 'get_trending_tags' THEN
      result :=  hivemind_endpoints.condenser_api_get_trending_tags(__params);
    WHEN __method_type = 'get_state' THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('condenser_api get state is not supported');
    WHEN __method_type = 'get_account_reputations' THEN
      result := hivemind_endpoints.condenser_api_get_account_reputations(__params, /* _fat_node_style */ True);
    WHEN __method_type = 'get_blog' THEN
      result := hivemind_endpoints.condenser_api_get_blog(__params, /* _get_entries */ False);
    WHEN __method_type = 'get_blog_entries' THEN
      result := hivemind_endpoints.condenser_api_get_blog(__params, /* _get_entries */ True);
    WHEN __method_type = 'get_content' THEN
      result := hivemind_endpoints.condenser_api_get_content(__params, /* _get_replies */ False, /* _content_additions */ True);
    WHEN __method_type = 'get_content_replies' THEN
      result := hivemind_endpoints.condenser_api_get_content(__params, /* _get_replies */ True, /* _content_additions */ True);
    WHEN __method_type = 'get_followers' THEN
      result := hivemind_endpoints.condenser_api_get_followers(__params, /* _called_from_condenser_api */ True);
    WHEN __method_type = 'get_following' THEN
      result := hivemind_endpoints.condenser_api_get_following(__params, /* _called_from_condenser_api */ True);
    WHEN __method_type = 'get_active_votes' THEN
      result := hivemind_endpoints.condenser_api_get_active_votes(__params);
    WHEN __method_type = 'get_discussions_by_blog' THEN
      result :=  hivemind_endpoints.condenser_api_get_discussions_by_blog_or_feed(__params, /* by_blog */ True);
    WHEN __method_type = 'get_discussions_by_feed' THEN
      result :=  hivemind_endpoints.condenser_api_get_discussions_by_blog_or_feed(__params, /* by_blog */ False);
    WHEN __method_type = 'get_discussions_by_author_before_date' THEN
      result :=  hivemind_endpoints.condenser_api_get_discussions_by_author_before_date(__params);
    WHEN __method_type = 'get_discussions_by_comments' THEN
      result :=  hivemind_endpoints.condenser_api_get_discussions_by_comments(__params);
    WHEN __method_type = 'get_replies_by_last_update' THEN
      result :=  hivemind_endpoints.condenser_api_get_replies_by_last_update(__params);
    WHEN __method_type = 'get_discussions_by_created' THEN
      result :=  hivemind_endpoints.condenser_api_get_discussions_by(__params, 'created'::hivemind_postgrest_utilities.ranked_post_sort_type);
    WHEN __method_type = 'get_discussions_by_hot' THEN
      result :=  hivemind_endpoints.condenser_api_get_discussions_by(__params, 'hot'::hivemind_postgrest_utilities.ranked_post_sort_type);
    WHEN __method_type = 'get_discussions_by_trending' THEN
      result :=  hivemind_endpoints.condenser_api_get_discussions_by(__params, 'trending'::hivemind_postgrest_utilities.ranked_post_sort_type);
    WHEN __method_type = 'get_post_discussions_by_payout' THEN
      result :=  hivemind_endpoints.condenser_api_get_discussions_by(__params, 'payout'::hivemind_postgrest_utilities.ranked_post_sort_type);
    WHEN __method_type = 'get_comment_discussions_by_payout' THEN
      result :=  hivemind_endpoints.condenser_api_get_discussions_by(__params, 'payout_comments'::hivemind_postgrest_utilities.ranked_post_sort_type);
    WHEN __method_type = 'get_account_votes' THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('get_account_votes is no longer supported, for details see https://hive.blog/steemit/@steemitdev/additional-public-api-change');
    ELSE
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_method_not_found_exception('condenser_api.' || __method_type);
  END CASE;
  RETURN result;
END;
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_follow_api_method;
CREATE FUNCTION hivemind_postgrest_utilities.get_follow_api_method(IN __method_type TEXT, IN __params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  result JSONB;
BEGIN
  CASE
    WHEN __method_type = 'get_account_reputations' THEN
      result := hivemind_endpoints.condenser_api_get_account_reputations(__params, /* _fat_node_style */ False);
    WHEN __method_type = 'get_blog' THEN
      result := hivemind_endpoints.condenser_api_get_blog(__params, /* _get_entries */ False);
    WHEN __method_type = 'get_blog_entries' THEN
      result := hivemind_endpoints.condenser_api_get_blog(__params, /* _get_entries */ True);
    WHEN __method_type = 'get_follow_count' THEN
      result :=  hivemind_endpoints.condenser_api_get_follow_count(__params);
    WHEN __method_type = 'get_reblogged_by' THEN
      result := hivemind_endpoints.condenser_api_get_reblogged_by(__params);
    WHEN __method_type = 'get_followers' THEN
      result := hivemind_endpoints.condenser_api_get_followers(__params, /* _called_from_condenser_api */ False);
    WHEN __method_type = 'get_following' THEN
      result := hivemind_endpoints.condenser_api_get_following(__params, /* _called_from_condenser_api */ False);
    ELSE
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_method_not_found_exception('follow_api.' || __method_type);
  END CASE;
  RETURN result;
END;
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_bridge_method;
CREATE FUNCTION hivemind_postgrest_utilities.get_bridge_method(IN __method_type TEXT, IN __params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  result JSONB;
BEGIN
  CASE
    WHEN __method_type = 'get_community' THEN
      result := hivemind_endpoints.bridge_api_get_community(__params);
    WHEN __method_type = 'get_community_context' THEN
      result := hivemind_endpoints.bridge_api_get_community_context(__params);
    WHEN __method_type = 'get_post' THEN
      result := hivemind_endpoints.bridge_api_get_post(__params);
    WHEN __method_type = 'get_payout_stats' THEN
      result := hivemind_endpoints.bridge_api_get_payout_stats(__params);
    WHEN __method_type = 'get_account_posts' THEN
      result := hivemind_endpoints.bridge_api_get_account_posts(__params);
    WHEN __method_type = 'get_relationship_between_accounts' THEN
      result := hivemind_endpoints.bridge_api_get_relationship_between_accounts(__params);
    WHEN __method_type = 'unread_notifications' THEN
      result := hivemind_endpoints.bridge_api_unread_notifications(__params);
    WHEN __method_type = 'get_ranked_posts' THEN
      result := hivemind_endpoints.bridge_api_get_ranked_posts(__params);
    WHEN __method_type = 'account_notifications' THEN
      result := hivemind_endpoints.bridge_api_account_notifications(__params);
    WHEN __method_type = 'post_notifications' THEN
      result := hivemind_endpoints.bridge_api_post_notifications(__params);
    WHEN __method_type = 'list_subscribers' THEN
      result := hivemind_endpoints.bridge_api_list_subscribers(__params);
    WHEN __method_type = 'get_trending_topics' THEN
      result := hivemind_endpoints.bridge_api_get_trending_topics(__params);
    WHEN __method_type = 'list_communities' THEN
      result := hivemind_endpoints.bridge_api_list_communities(__params);
    WHEN __method_type = 'get_discussion' THEN
      result := hivemind_endpoints.bridge_api_get_discussion(__params);
    WHEN __method_type = 'get_post_header' THEN
      result := hivemind_endpoints.bridge_api_get_posts_header(__params);
    WHEN __method_type = 'normalize_post' THEN
      -- according to python code, there are no checks if anything is good, just extract author & permlink and call get_post
      result := hivemind_endpoints.bridge_api_get_post(jsonb_build_object('author', __params->'post'->>'author', 'permlink', __params->'post'->>'permlink'));
    WHEN __method_type = 'get_profile' THEN
      result := hivemind_endpoints.bridge_api_get_profile(__params);
    WHEN __method_type = 'get_profiles' THEN
      result := hivemind_endpoints.bridge_api_get_profiles(__params);
    WHEN __method_type = 'list_muted_reasons_enum' THEN
      result := hivemind_postgrest_utilities.get_muted_reason_map();
    WHEN __method_type = 'does_user_follow_any_lists' THEN
      result := hivemind_endpoints.bridge_api_does_user_follow_any_lists(__params);
    WHEN __method_type = 'get_follow_list' THEN
      result := hivemind_endpoints.bridge_api_get_follow_list(__params);
    WHEN __method_type = 'list_community_roles' THEN
      result := hivemind_endpoints.bridge_api_list_community_roles(__params);
    WHEN __method_type = 'list_all_subscriptions' THEN
      result := hivemind_endpoints.bridge_api_list_all_subscriptions(__params);
    WHEN __method_type = 'list_pop_communities' THEN
      result := hivemind_endpoints.bridge_api_list_pop_communities(__params);
    ELSE
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_method_not_found_exception('bridge_api' || __method_type);
  END CASE;
  RETURN result;
END;
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_tags_api_method;
CREATE FUNCTION hivemind_postgrest_utilities.get_tags_api_method(IN __method_type TEXT, IN __params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  result JSONB;
BEGIN
  CASE
    WHEN __method_type = 'get_content_replies' THEN
      result := hivemind_endpoints.condenser_api_get_content(__params, /* _get_replies */ True, /* _content_additions */ False);
    WHEN __method_type = 'get_discussion' THEN
      result := hivemind_endpoints.condenser_api_get_content(__params, /* _get_replies */ False, /* _content_additions */ False);
    WHEN __method_type = 'get_discussions_by_blog' THEN
      result := hivemind_endpoints.condenser_api_get_discussions_by_blog_or_feed(__params, /* by_blog */ True);
    WHEN __method_type = 'get_discussions_by_comments' THEN
      result := hivemind_endpoints.condenser_api_get_discussions_by_comments(__params);
    WHEN __method_type = 'get_discussions_by_author_before_date' THEN
      result :=  hivemind_endpoints.condenser_api_get_discussions_by_author_before_date(__params);
    WHEN __method_type = 'get_discussions_by_created' THEN
      result :=  hivemind_endpoints.condenser_api_get_discussions_by(__params, 'created'::hivemind_postgrest_utilities.ranked_post_sort_type);
    WHEN __method_type = 'get_discussions_by_hot' THEN
      result :=  hivemind_endpoints.condenser_api_get_discussions_by(__params, 'hot'::hivemind_postgrest_utilities.ranked_post_sort_type);
    WHEN __method_type = 'get_discussions_by_trending' THEN
      result :=  hivemind_endpoints.condenser_api_get_discussions_by(__params, 'trending'::hivemind_postgrest_utilities.ranked_post_sort_type);
    WHEN __method_type = 'get_post_discussions_by_payout' THEN
      result :=  hivemind_endpoints.condenser_api_get_discussions_by(__params, 'payout'::hivemind_postgrest_utilities.ranked_post_sort_type);
    WHEN __method_type = 'get_comment_discussions_by_payout' THEN
      result :=  hivemind_endpoints.condenser_api_get_discussions_by(__params, 'payout_comments'::hivemind_postgrest_utilities.ranked_post_sort_type);
    WHEN __method_type = 'get_account_votes' THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('get_account_votes is no longer supported, for details see https://hive.blog/steemit/@steemitdev/additional-public-api-change');
    ELSE
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_method_not_found_exception('tags_api' || __method_type);
  END CASE;
  RETURN result;
END;
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_database_api_method;
CREATE FUNCTION hivemind_postgrest_utilities.get_database_api_method(IN __method_type TEXT, IN __params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  result JSONB;
BEGIN
  CASE
    WHEN __method_type = 'find_votes' THEN
      result := hivemind_endpoints.database_api_find_votes(__params);
    WHEN __method_type = 'list_votes' THEN
      result := hivemind_endpoints.database_api_list_votes(__params);
    WHEN __method_type = 'find_comments' THEN
      result := hivemind_endpoints.database_api_find_comments(__params);
    ELSE
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_method_not_found_exception('database_api' || __method_type);
  END CASE;
  RETURN result;
END;
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_hive_api_method;
CREATE FUNCTION hivemind_postgrest_utilities.get_hive_api_method(IN __method_type TEXT, IN __params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  result JSONB;
BEGIN
  CASE
    WHEN __method_type = 'get_info' THEN
      result := hivemind_endpoints.hive_api_get_info(__params);
    WHEN __method_type = 'db_head_state' THEN
      result := hivemind_endpoints.hive_api_db_head_state(__params);
    ELSE
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_method_not_found_exception('hive_api' || __method_type);
  END CASE;
  RETURN result;
END;
$$
;
