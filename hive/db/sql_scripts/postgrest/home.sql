DROP FUNCTION IF EXISTS hivemind_endpoints.home;
CREATE FUNCTION hivemind_endpoints.home(JSON)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  __request_data JSON = $1;
  __id JSONB;
  __method TEXT;
  __params JSON;
  __params_jsonb JSONB;
  __request_params JSONB;
BEGIN
  __id = __request_data->'id';
  __method = __request_data->>'method';

  __params = __request_data->'params';
  
  IF __method NOT IN ('hive.db_head_state', 'condenser.get_trending_tags', 
                      'bridge.list_pop_communities', 'bridge.get_payout_stats', 
                      'bridge.get_trending_topics','bridge.list_muted_reasons_enum'
                     ) THEN
    IF __params is NULL THEN
      RETURN jsonb_build_object('jsonrpc', '2.0', 'error', 'no parameters passed', 'id', __id);
    END IF;
  END IF;

  __params_jsonb = __params::JSONB;
  __request_params = hivemind_postgrest_utilities.check_general_json_format(__request_data->>'jsonrpc',
                                                                            __method,
                                                                            __params_jsonb,
                                                                            __id);

  RETURN jsonb_build_object(
    'jsonrpc', '2.0',
    'id', __id,
    'result', hivemind_postgrest_utilities.dispatch(__request_params->>'api_type',
                                                    __request_params->>'method_type',
                                                    __params_jsonb
    )
  );

  EXCEPTION
    WHEN raise_exception THEN
      RETURN jsonb_build_object('jsonrpc', '2.0', 'error', SQLERRM::JSONB, 'id', __id);
END
$$
;


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
