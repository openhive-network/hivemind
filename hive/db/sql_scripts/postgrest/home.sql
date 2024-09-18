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

  __result JSON;
  __api_type TEXT;
  __method_type TEXT;
  __json_with_params_is_object BOOLEAN;
  __method_is_call BOOLEAN;
  __exception_message TEXT;
  __exception JSONB;
BEGIN
  __jsonrpc = (__request_data->>'jsonrpc');
  __method = (__request_data->>'method');
  __params = (__request_data->'params');
  __id = (__request_data->'id');

  SELECT NULL::JSON INTO __result;

  IF __jsonrpc != '2.0' OR __jsonrpc IS NULL OR __params IS NULL OR __id IS NULL OR __method IS NULL THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_invalid_json_format_exception('Invalid JSON-RPC');
  END IF;

  if lower(__method) = 'call' THEN
    if json_array_length(__params) < 2 THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_invalid_json_format_exception('Invalid JSON-RPC');
    END IF;
    __api_type = __params->>0;
    __method_type = __params->>1;
    __params = __params->>2;
    __json_with_params_is_object = False;
    __method_is_call = True;
  ELSE
    SELECT substring(__method FROM '^[^.]+') INTO __api_type;
    SELECT substring(__method FROM '[^.]+$') INTO __method_type;
    __method_is_call = False;
    IF json_typeof(__params) = 'object' THEN
      __json_with_params_is_object = True;
    ELSEIF json_typeof(__params) = 'array' THEN
      IF json_array_length(__params) <> 0 THEN
        __json_with_params_is_object = False;
      ELSE
        __json_with_params_is_object = True;
      END IF;
    ELSE
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_invalid_json_format_exception('Invalid JSON format:' || json_typeof(__params)::text);
    END IF;
  END IF;

  __result := hivemind_postgrest_utilities.dispatch(__api_type, __method_type, __json_with_params_is_object, __method_is_call, __params);

  RETURN jsonb_build_object(
      'jsonrpc', '2.0',
      'result', __result,
      'id', __id
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
