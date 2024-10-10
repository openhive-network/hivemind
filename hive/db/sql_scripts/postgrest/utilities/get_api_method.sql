DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_condenser_api_method;
CREATE FUNCTION hivemind_postgrest_utilities.get_condenser_api_method(IN __method_type TEXT, IN __json_with_params_is_object BOOLEAN, IN __params JSONB)
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
      result :=  hivemind_endpoints.condenser_api_get_follow_count(__json_with_params_is_object, __params);
    WHEN __method_type = 'get_reblogged_by' THEN
      result :=  hivemind_endpoints.condenser_api_get_reblogged_by(__json_with_params_is_object, __params);
    WHEN __method_type = 'get_trending_tags' THEN
      result :=  hivemind_endpoints.condenser_api_get_trending_tags(__json_with_params_is_object, __params);
    WHEN __method_type = 'get_state' THEN
      result :=  hivemind_endpoints.condenser_api_get_state(__json_with_params_is_object, __params);
    WHEN __method_type = 'get_account_reputations' THEN
      result := hivemind_endpoints.condenser_api_get_account_reputations(__json_with_params_is_object, __params, /* _fat_node_style */ True);
    WHEN __method_type = 'get_blog' THEN
      result := hivemind_endpoints.condenser_api_get_blog(__json_with_params_is_object, __params, /* _get_entries */ False);
    WHEN __method_type = 'get_blog_entries' THEN
      result := hivemind_endpoints.condenser_api_get_blog(__json_with_params_is_object, __params, /* _get_entries */ True);
    WHEN __method_type = 'get_content' THEN
      result := hivemind_endpoints.condenser_api_get_content(__json_with_params_is_object, __params, /* _get_replies */ False, /* _content_additions */ True);
    WHEN __method_type = 'get_content_replies' THEN
      result := hivemind_endpoints.condenser_api_get_content(__json_with_params_is_object, __params, /* _get_replies */ True, /* _content_additions */ True);
    WHEN __method_type = 'get_followers' THEN
      result := hivemind_endpoints.condenser_api_get_followers(__json_with_params_is_object, __params);
    WHEN __method_type = 'get_following' THEN
      result := hivemind_endpoints.condenser_api_get_following(__json_with_params_is_object, __params);
    WHEN __method_type = 'get_active_votes' THEN
      result := hivemind_endpoints.condenser_api_get_active_votes(__json_with_params_is_object, __params);
    ELSE
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_method_not_found_exception(__method_type);
  END CASE;
  RETURN result;
END;
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_follow_api_method;
CREATE FUNCTION hivemind_postgrest_utilities.get_follow_api_method(IN __method_type TEXT, IN __json_with_params_is_object BOOLEAN, IN __params JSONB)
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
      result := hivemind_endpoints.condenser_api_get_account_reputations(__json_with_params_is_object, __params, /* _fat_node_style */ False);
    WHEN __method_type = 'get_blog' THEN
      result := hivemind_endpoints.condenser_api_get_blog(__json_with_params_is_object, __params, /* _get_entries */ False);
    WHEN __method_type = 'get_blog_entries' THEN
      result := hivemind_endpoints.condenser_api_get_blog(__json_with_params_is_object, __params, /* _get_entries */ True);
    WHEN __method_type = 'get_follow_count' THEN
      result :=  hivemind_endpoints.condenser_api_get_follow_count(__json_with_params_is_object, __params);
    WHEN __method_type = 'get_reblogged_by' THEN
      result := hivemind_endpoints.condenser_api_get_reblogged_by(__json_with_params_is_object, __params);
    WHEN __method_type = 'get_followers' THEN
      result := hivemind_endpoints.condenser_api_get_followers(__json_with_params_is_object, __params);
    WHEN __method_type = 'get_following' THEN
      result := hivemind_endpoints.condenser_api_get_following(__json_with_params_is_object, __params);
    ELSE
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_method_not_found_exception(__method_type);
  END CASE;
  RETURN result;
END;
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_bridge_method;
CREATE FUNCTION hivemind_postgrest_utilities.get_bridge_method(IN __method_type TEXT, IN __json_with_params_is_object BOOLEAN, IN __params JSONB)
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
      result := hivemind_endpoints.bridge_api_get_community(__json_with_params_is_object, __params);
    WHEN __method_type = 'get_community_context' THEN
      result := hivemind_endpoints.bridge_api_get_community_context(__json_with_params_is_object, __params);
    WHEN __method_type = 'get_post' THEN
      result := hivemind_endpoints.bridge_api_get_posts(__json_with_params_is_object, __params);
    WHEN __method_type = 'get_payout_stats' THEN
      result := hivemind_endpoints.bridge_api_get_payout_stats(__json_with_params_is_object, __params);
    ELSE
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_method_not_found_exception(__method_type);
  END CASE;
  RETURN result;
END;
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_tags_api_method;
CREATE FUNCTION hivemind_postgrest_utilities.get_tags_api_method(IN __method_type TEXT, IN __json_with_params_is_object BOOLEAN, IN __params JSONB)
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
      result := hivemind_endpoints.condenser_api_get_content(__json_with_params_is_object, __params, /* _get_replies */ True, /* _content_additions */ False);
    WHEN __method_type = 'get_discussion' THEN
      result := hivemind_endpoints.condenser_api_get_content(__json_with_params_is_object, __params, /* _get_replies */ False, /* _content_additions */ False);
    ELSE
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_method_not_found_exception(__method_type);
  END CASE;
  RETURN result;
END;
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_database_api_method;
CREATE FUNCTION hivemind_postgrest_utilities.get_database_api_method(IN __method_type TEXT, IN __json_with_params_is_object BOOLEAN, IN __params JSONB)
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
      result := hivemind_endpoints.database_api_find_votes(__json_with_params_is_object, __params);
    WHEN __method_type = 'list_votes' THEN
      result := hivemind_endpoints.database_api_list_votes(__json_with_params_is_object, __params);
    ELSE
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_method_not_found_exception(__method_type);
  END CASE;
  RETURN result;
END;
$$
;