DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.dispatch;
CREATE FUNCTION hivemind_postgrest_utilities.dispatch(IN __api_type TEXT, IN __method_type TEXT, IN __params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  result JSONB;
BEGIN
  CASE
    WHEN __api_type = 'condenser_api' THEN
      result := hivemind_postgrest_utilities.get_condenser_api_method(__method_type, __params);
    WHEN __api_type = 'follow_api' THEN
      result := hivemind_postgrest_utilities.get_follow_api_method(__method_type, __params);
    WHEN __api_type = 'bridge' THEN
      result := hivemind_postgrest_utilities.get_bridge_method(__method_type, __params);
    WHEN __api_type = 'tags_api' THEN
      result := hivemind_postgrest_utilities.get_tags_api_method(__method_type, __params);
    WHEN __api_type = 'database_api' THEN
      result := hivemind_postgrest_utilities.get_database_api_method(__method_type, __params);
    WHEN __api_type = 'hive' THEN
      result := hivemind_postgrest_utilities.get_hive_api_method(__method_type, __params);
    ELSE
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_api_not_found_exception(__api_type);
  END CASE;
  RETURN result;
END;
$$
;
