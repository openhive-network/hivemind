DROP FUNCTION IF EXISTS hivemind_endpoints.database_api_list_comments;
CREATE FUNCTION hivemind_endpoints.database_api_list_comments(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _start JSONB;
  _limit INT;
BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"start","limit","order"}', '{"array","number","string"}');

  _start = hivemind_postgrest_utilities.parse_array_argument_from_json(_params, _json_is_object, 'start', 0, True);
  _limit = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'limit', 1, False);
  _limit = hivemind_postgrest_utilities.valid_number(_limit, 1000, 1, 1000, 'limit');

  CASE hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'order', 2, True)
    WHEN 'by_cashout_time' THEN RETURN hivemind_postgrest_utilities.list_comments_by_cashout_time(_start, _limit);
    WHEN 'by_root' THEN RETURN hivemind_postgrest_utilities.list_comments_by_root_or_parent(_start, _limit, True);
    WHEN 'by_parent' THEN RETURN hivemind_postgrest_utilities.list_comments_by_root_or_parent(_start, _limit, False);
    WHEN 'by_last_update' THEN RETURN hivemind_postgrest_utilities.list_comments_by_last_update(_start, _limit);
    WHEN 'by_author_last_update' THEN RETURN hivemind_postgrest_utilities.list_comments_by_author_last_update(_start, _limit);
    WHEN 'by_permlink' THEN RETURN hivemind_postgrest_utilities.list_comments_by_permlink(_start, _limit);
    ELSE RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Unsupported order, valid orders: by_cashout_time, by_permlink, by_root, by_parent, by_last_update, by_author_last_update');
  END CASE;
END;
$$
;