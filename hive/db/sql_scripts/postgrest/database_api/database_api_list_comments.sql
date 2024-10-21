DROP FUNCTION IF EXISTS hivemind_endpoints.database_api_list_comments;
CREATE FUNCTION hivemind_endpoints.database_api_list_comments(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE

BEGIN
  RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('database api list comments not implemented yet');
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"start","limit","order"}', '{"array","number","string"}');

END;
$$
;