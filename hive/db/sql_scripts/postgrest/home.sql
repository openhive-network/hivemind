DROP FUNCTION IF EXISTS hivemind_endpoints.home;
CREATE FUNCTION hivemind_endpoints.home(JSON)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  __request_data JSON = $1;
  __jsonrpc TEXT;
  __method TEXT;
  __params JSON;
  __id JSON;

  __result JSONB;
  __exception_message TEXT;
  __exception JSONB;
BEGIN
  __jsonrpc = (__request_data->>'jsonrpc');
  __method = (__request_data->>'method');
  __params = (__request_data->'params');
  __id = (__request_data->'id');

  SELECT hivemind_postgrest_utilities.check_general_json_format(__jsonrpc, __method, __params, __id) INTO __result;

  RETURN jsonb_build_object(
    'jsonrpc', '2.0',
    'id', __id,
    'result', hivemind_postgrest_utilities.dispatch(
                                                    __result->>'api_type'::TEXT,
                                                    __result->>'method_type'::TEXT,
                                                    (__result->>'json_with_params_is_object')::BOOLEAN,
                                                    (__result->>'method_is_call')::BOOLEAN,
                                                    (__result->>'params')::JSON
    )
  );

  EXCEPTION
    WHEN raise_exception THEN
      __exception = SQLERRM;
      __exception = jsonb_set(__exception, '{id}', __id::jsonb);
      RETURN __exception ;
    WHEN invalid_text_representation THEN
      RETURN hivemind_postgrest_utilities.raise_uint_exception(__id);
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS __exception_message = message_text;
      RETURN hivemind_postgrest_utilities.raise_operation_param_exception(__exception_message, __id);
END
$$
;
