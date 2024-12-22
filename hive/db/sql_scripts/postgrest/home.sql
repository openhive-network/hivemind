DROP FUNCTION IF EXISTS hivemind_endpoints.home;
CREATE FUNCTION hivemind_endpoints.home(JSON)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  __request_data JSON = $1;
  __id TEXT;
  __jsonrpc TEXT;
  __method TEXT;
  __params JSON;
  __api_type TEXT;
  __method_type TEXT;
  __params_jsonb JSONB;
BEGIN

  __jsonrpc = __request_data->>'jsonrpc';
  IF __jsonrpc != '2.0' THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_invalid_json_format_exception('Invalid JSON-RPC');
  END IF;

  __id = __request_data->>'id';
  IF __id IS NULL THEN
    return jsonb_build_object('jsonrpc', '2.0', 'error', 'id required');
  END IF;

  __method = __request_data->>'method';
  if __method is NULL THEN
    RETURN jsonb_build_object('jsonrpc', '2.0', 'error', 'no method passed', 'id', __id);
  END IF;

  --early check to reject methods that require parameters
  __params = __request_data->'params';
  IF __method NOT IN ('call', 'hive.db_head_state', 'condenser.get_trending_tags', 
                      'bridge.list_pop_communities', 'bridge.get_payout_stats', 
                      'bridge.get_trending_topics','bridge.list_muted_reasons_enum'
                     ) THEN
    IF __params is NULL THEN
      RETURN jsonb_build_object('jsonrpc', '2.0', 'error', 'this method requires parameters', 'id', __id);
    END IF;
  END IF;

  __params_jsonb = __params::JSONB;
  --handle 'call' method (probably should remove this if condition, no one uses and it is inefficiently implemented)
  if lower(__method) = 'call' THEN
    if jsonb_array_length(__params_jsonb) < 2 THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_invalid_json_format_exception('Invalid JSON-RPC');
    END IF;
    __api_type = __params_jsonb->>0;
    __method_type = __params_jsonb->>1;
    -- this 'call' keyword in test cases gives another error messages, so it is important
    __params = jsonb_build_object('used_call_keyword', True, 'params', __params_jsonb->2);
  ELSE
    SELECT split_part(__method, '.', 1) INTO __api_type;
    SELECT split_part(__method, '.', 2) INTO __method_type;
  END IF;

  
  RETURN jsonb_build_object( 'jsonrpc', '2.0', 'id', __id, 'result', hivemind_postgrest_utilities.dispatch(__api_type, __method_type, __params_jsonb) );

  EXCEPTION
    WHEN raise_exception THEN
      RETURN jsonb_build_object('jsonrpc', '2.0', 'error', SQLERRM::JSONB, 'id', __id);
END
$$
;

/*
DROP FUNCTION IF EXISTS hivemind_endpoints.home_test;
CREATE FUNCTION hivemind_endpoints.home_test(json_rpc JSON)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  __request_data JSON = $1;
  __jsonrpc TEXT;
  __method TEXT;
  __params JSONB;
  __id JSONB;

  __result JSONB;
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
                                                    __result->>'api_type',
                                                    __result->>'method_type',
                                                    (__result->'json_with_params_is_object')::BOOLEAN,
                                                    __result->'params'
    )
  );

  EXCEPTION
    WHEN raise_exception THEN
      RETURN jsonb_build_object(
        'jsonrpc', '2.0',
        'error', SQLERRM::JSONB,
        'id', __id
      );
END
$$
;
*/