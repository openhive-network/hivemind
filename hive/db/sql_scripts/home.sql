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
  __json_type TEXT;
  __exception_message TEXT;
  __exception JSONB;
BEGIN
  __jsonrpc = (__request_data->>'jsonrpc');
  __method = (__request_data->>'method');
  __params = (__request_data->'params');
  __id = (__request_data->'id');

  SELECT NULL::JSON INTO __result;

  IF __jsonrpc != '2.0' OR __jsonrpc IS NULL OR __params IS NULL OR __id IS NULL THEN
    RETURN hivemind_helpers.raise_exception(-32600, 'Invalid JSON-RPC');
  END IF;

  SELECT substring(__method FROM '^[^.]+') INTO __api_type;
  SELECT substring(__method FROM '[^.]+$') INTO __method_type;
  SELECT json_typeof(__params) INTO __json_type;

  __is_legacy_style := __api_type = 'condenser_api';

  IF __api_type = 'bridge' THEN
    IF __method_type = 'get_community' THEN
      SELECT hivemind_endpoints.get_community(__params, __json_type, __id) INTO __result;
    ELSEIF __method_type = 'get_community_context' THEN
      SELECT hivemind_endpoints.get_community_context(__params, __json_type, __id) INTO __result;
    ELSEIF __method_type = 'list_pop_communities' THEN
      SELECT hivemind_endpoints.list_pop_communities(__params, __json_type, __id) INTO __result;
    ELSEIF __method_type = 'list_all_subscriptions' THEN
      SELECT hivemind_endpoints.list_all_subscriptions(__params, __json_type, __id) INTO __result;
    ELSEIF __method_type = 'list_subscribers' THEN
      SELECT hivemind_endpoints.list_subscribers(__params, __json_type, __id) INTO __result;
    ELSEIF __method_type = 'list_communities' THEN
      SELECT hivemind_endpoints.list_communities(__params, __json_type, __id) INTO __result;
    ELSEIF __method_type = 'list_community_roles' THEN
      SELECT hivemind_endpoints.list_community_roles(__params, __json_type, __id) INTO __result;
    ELSEIF __method_type = 'account_notifications' THEN
      SELECT hivemind_endpoints.account_notifications(__params, __json_type, __id) INTO __result;
    END IF;
/*
  ELSEIF __api_type = 'block_api' THEN
    IF __method_type = 'get_block' THEN
      SELECT hivemind_endpoints.call_get_block( __params, __json_type, __id) INTO __result;
    ELSEIF __method_type = 'get_block_header' THEN
      SELECT hivemind_endpoints.call_get_block_header( __params, __json_type, __id) INTO __result;
    ELSEIF __method_type = 'get_block_range' THEN
      SELECT hivemind_endpoints.call_get_block_range( __params, __json_type, __id) INTO __result;
    END IF;
*/
  END IF;

  IF __result IS NULL THEN
    RETURN hivemind_helpers.raise_exception(-32601, 'Method not found', __method, __id);
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
      RETURN hivemind_helpers.raise_uint_exception(_id);
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS __exception_message = message_text;
      RETURN hivemind_helpers.raise_operation_param(__exception_message, _id);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_endpoints.get_community;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_community(_params JSON, _json_type TEXT, _id JSON = NULL)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
    __accepted_params TEXT[] := ARRAY['name','observer'];
    __name TEXT = NULL;
    __observer TEXT = NULL;
    __exception_message TEXT;
    __extra_param TEXT;
BEGIN
  BEGIN
-------------extra-params
    IF _json_type = 'object' THEN
      SELECT m.key INTO __extra_param
      FROM json_each(_params) as m
      WHERE NOT (m.key = ANY(__accepted_params));

      IF __extra_param IS NOT NULL THEN
        RETURN hivemind_helpers.raise_extra_arg(__extra_param, _id);
      END IF;
    ELSE
      IF json_array_length(_params) > 2 THEN
        RETURN hivemind_helpers.raise_invalid_array_exception(_id);
      END IF;
    END IF;

-------------name (community)
    __name = hivemind_helpers.parse_argument(_params, _json_type, 'name', 0);

    IF __name IS NULL THEN
      RETURN hivemind_helpers.raise_missing_arg('name', _id);
    END IF;

    IF json_typeof(_params->'name') != 'string' THEN 
      RETURN hivemind_helpers.raise_community_exception(_id);
    END IF; 
-------------observer
    __observer = hivemind_helpers.parse_argument(_params, _json_type, 'observer', 1);

    IF json_typeof(_params->'observer') != 'string' AND __observer IS NOT NULL THEN 
      RETURN hivemind_helpers.raise_account_exception(_id);
    END IF; 
-------------return
    RETURN (
      SELECT to_json(row) FROM (
        SELECT * FROM hivemind_helpers.get_community(__name::TEXT, __observer::TEXT)
      ) row );
  EXCEPTION
    WHEN invalid_text_representation THEN
      RETURN hivemind_helpers.raise_uint_exception(_id);
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS __exception_message = message_text;
      RETURN hivemind_helpers.raise_operation_param(__exception_message, _id);
  END;
END
$$
;

DROP FUNCTION IF EXISTS hivemind_endpoints.get_community_context;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_community_context(_params JSON, _json_type TEXT, _id JSON = NULL)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
    __accepted_params TEXT[] := ARRAY['name','account'];
    __name TEXT = NULL;
    __account TEXT = NULL;
    __exception_message TEXT;
    __extra_param TEXT;
BEGIN
  BEGIN
-------------extra-params
    IF _json_type = 'object' THEN
      SELECT m.key INTO __extra_param
      FROM json_each(_params) as m
      WHERE NOT (m.key = ANY(__accepted_params));

      IF __extra_param IS NOT NULL THEN
        RETURN hivemind_helpers.raise_extra_arg(__extra_param, _id);
      END IF;
    ELSE
      IF json_array_length(_params) > 2 THEN
        RETURN hivemind_helpers.raise_invalid_array_exception(_id);
      END IF;
    END IF;
-------------name (community)
    __name = hivemind_helpers.parse_argument(_params, _json_type, 'name', 0);

    IF __name IS NULL THEN
      RETURN hivemind_helpers.raise_missing_arg('name', _id);
    END IF;

    IF json_typeof(_params->'name') != 'string' THEN 
      RETURN hivemind_helpers.raise_community_exception(_id);
    END IF; 
-------------account
    __account = hivemind_helpers.parse_argument(_params, _json_type, 'account', 1);

    IF __account IS NULL THEN
      RETURN hivemind_helpers.raise_missing_arg('account', _id);
    END IF;

    IF json_typeof(_params->'account') != 'string' AND __account IS NOT NULL THEN 
      RETURN hivemind_helpers.raise_account_exception(_id);
    END IF; 
-------------return
    RETURN (
      SELECT to_json(row) FROM (
        SELECT * FROM hivemind_helpers.get_community_context(__name::TEXT, __account::TEXT)
      ) row );
  EXCEPTION
    WHEN invalid_text_representation THEN
      RETURN hivemind_helpers.raise_uint_exception(_id);
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS __exception_message = message_text;
      RETURN hivemind_helpers.raise_operation_param(__exception_message, _id);
  END;
END
$$
;
