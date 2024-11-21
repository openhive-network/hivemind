DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_list_communities;
CREATE FUNCTION hivemind_endpoints.bridge_api_list_communities(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
    _limit INTEGER;
    _sort TEXT;
    _search TEXT;
    _observer_id INT;
    _community_id INT;
BEGIN
    PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"last", "limit", "query", "sort", "observer"}', '{"string", "number", "string", "string", "string"}', 0);

    _limit := hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'limit', 1, False);
    _limit := hivemind_postgrest_utilities.valid_number(_limit, 100, 1, 100, 'limit');

    _search := hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'query', 2, False);
    _sort := COALESCE(hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'sort', 3, False), 'rank');

    _observer_id = 
      hivemind_postgrest_utilities.find_account_id(
        hivemind_postgrest_utilities.valid_account(
          hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'observer', 1, False),
        True),
      True);
    
    _community_id = 
      hivemind_postgrest_utilities.find_community_id(
        hivemind_postgrest_utilities.valid_community(
          hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'last', 0, False),
        True),
      True);

    ASSERT _sort IS NOT NULL;

    CASE
      WHEN _sort IS NULL THEN RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('sort type in null list_communities');
      WHEN _sort = 'rank' THEN RETURN hivemind_postgrest_utilities.list_communities_by_rank(_observer_id, _community_id, _search, _limit);
      WHEN _sort = 'new' THEN RETURN hivemind_postgrest_utilities.list_communities_by_new(_observer_id, _community_id, _search, _limit);
      WHEN _sort = 'subs' THEN RETURN hivemind_postgrest_utilities.list_communities_by_subs(_observer_id, _community_id, _search, _limit);
      ELSE RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_community_exception('Unsupported sort, valid sorts: rank, new, subs');
    END CASE;
END
$$
;