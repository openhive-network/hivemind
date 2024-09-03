DROP FUNCTION IF EXISTS hivemind_endpoints.home;
CREATE OR REPLACE FUNCTION hivemind_endpoints.home(JSON)
RETURNS JSONB
LANGUAGE 'plpgsql'
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
  __is_legacy_style BOOLEAN;
  __json_type_is_object BOOLEAN;
  __exception_message TEXT;
  __exception JSONB;
BEGIN
  __jsonrpc = (__request_data->>'jsonrpc');
  __method = (__request_data->>'method');
  __params = (__request_data->'params');
  __id = (__request_data->'id');

  SELECT NULL::JSON INTO __result;

  IF __jsonrpc != '2.0' OR __jsonrpc IS NULL OR __params IS NULL OR __id IS NULL OR __method IS NULL THEN
    RAISE EXCEPTION '%', hivemind_utilities.raise_invalid_json_format_exception('Invalid JSON-RPC');
  END IF;

  if lower(__method) = 'call' and json_typeof(__params) = 'array' THEN
    if json_array_length(__params) < 2 THEN
      RAISE EXCEPTION '%', hivemind_utilities.raise_invalid_json_format_exception('Invalid JSON-RPC');
    END IF;
    __api_type = __params->>0;
    __method_type = __params->>1;
    __params = __params->>2;
  ELSE
    SELECT substring(__method FROM '^[^.]+') INTO __api_type;
    SELECT substring(__method FROM '[^.]+$') INTO __method_type;
  END IF;

  IF json_typeof(__params) = 'object' THEN
    __json_type_is_object = True;
  ELSEIF json_typeof(__params) = 'array' THEN
    __json_type_is_object = False;
  ELSE
    RAISE EXCEPTION '%', hivemind_utilities.raise_invalid_json_format_exception('Invalid JSON format:' || json_typeof(__params)::text);
  END IF;

  __is_legacy_style := __api_type = 'condenser_api';

  IF __api_type = 'condenser_api' THEN
    IF __method_type = 'get_follow_count' THEN
      PERFORM hivemind_utilities.validate_json_parameters(__json_type_is_object, __params, '{"account":"string"}', 1, 1, '["string"]');
      SELECT hivemind_endpoints.condenser_api_get_follow_count(_account => hivemind_utilities.parse_string_argument_from_json(__params, __json_type_is_object, 'account', 0, True)) INTO __result;

    ELSEIF __method_type = 'get_reblogged_by' THEN
      PERFORM hivemind_utilities.validate_json_parameters(__json_type_is_object, __params, '{"author":"string","permlink":"string"}', 2, 2, '["string","string"]');
      SELECT hivemind_endpoints.condenser_api_get_reblogged_by(_author => hivemind_utilities.parse_string_argument_from_json(__params, __json_type_is_object, 'author', 0, True),
                                                               _permlink => hivemind_utilities.parse_string_argument_from_json(__params, __json_type_is_object, 'permlink', 1, True)) INTO __result;
    ELSEIF __method_type = 'get_trending_tags' THEN
      PERFORM hivemind_utilities.validate_json_parameters(__json_type_is_object, __params, '{"start_tag":"string","limit":"number"}', 0, 2, '["string","number"]');
      SELECT hivemind_endpoints.condenser_api_get_trending_tags(_start_tag => hivemind_utilities.parse_string_argument_from_json(__params, __json_type_is_object, 'start_tag', 0, False),
                                                                _limit => hivemind_utilities.parse_integer_argument_from_json(__params, __json_type_is_object, 'limit', 1, False)) INTO __result;
    ELSEIF __method_type = 'get_state' THEN
      PERFORM hivemind_utilities.validate_json_parameters(__json_type_is_object, __params, '{"path":"string"}', 0, 1, '["string"]');
      SELECT hivemind_endpoints.condenser_api_get_state(_path => hivemind_utilities.parse_string_argument_from_json(__params, __json_type_is_object, 'path', 0, False)) INTO __result;
    END IF;
  END IF;

  IF __result IS NULL THEN
    RAISE EXCEPTION '%', hivemind_utilities.raise_method_not_found_exception(__method);
  ELSEIF __result->'error' IS NULL THEN
    RETURN jsonb_build_object(
      'jsonrpc', '2.0',
      'result', __result,
      'id', __id
    );
  ELSE
    RETURN __result::JSONB;
  END IF;
  EXCEPTION
    WHEN raise_exception THEN
      __exception = SQLERRM;
      __exception = jsonb_set(__exception, '{id}', __id::jsonb);
      RETURN __exception ;
    WHEN invalid_text_representation THEN
      RETURN hivemind_utilities.raise_uint_exception(__id);
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS __exception_message = message_text;
      RETURN hivemind_utilities.raise_operation_param_exception(__exception_message, __id);
END
$$
;
