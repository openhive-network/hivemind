DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.check_general_json_format;
CREATE FUNCTION hivemind_postgrest_utilities.check_general_json_format(
    IN __jsonrpc TEXT,
    IN __method TEXT,
    IN __params JSON,
    IN __id JSON
) RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  __api_type TEXT;
  __method_type TEXT;
  __json_with_params_is_object BOOLEAN;
  __method_is_call BOOLEAN;
BEGIN
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

  RETURN jsonb_build_object(
    'api_type', __api_type,
    'method_type', __method_type,
    'params', __params,
    'json_with_params_is_object', __json_with_params_is_object,
    'method_is_call', __method_is_call
  );

END
$$
;