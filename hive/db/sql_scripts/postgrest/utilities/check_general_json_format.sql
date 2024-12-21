DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.check_general_json_format;
CREATE FUNCTION hivemind_postgrest_utilities.check_general_json_format(
    IN __jsonrpc TEXT,
    IN __method TEXT,
    IN __params JSONB,
    IN __id JSONB
) RETURNS JSONB
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
DECLARE
  __api_type TEXT;
  __method_type TEXT;
BEGIN
  IF __jsonrpc != '2.0' OR __jsonrpc IS NULL OR __params IS NULL OR __id IS NULL OR __method IS NULL THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_invalid_json_format_exception('Invalid JSON-RPC');
  END IF;

  if lower(__method) = 'call' THEN
    if jsonb_array_length(__params) < 2 THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_invalid_json_format_exception('Invalid JSON-RPC');
    END IF;
    __api_type = __params->>0;
    __method_type = __params->>1;

    -- this 'call' keyword in test cases gives another error messages, so it is important
    __params = jsonb_build_object('used_call_keyword', True,
                                  'params', __params->2);
  ELSE
    SELECT split_part(__method, '.', 1) INTO __api_type;
    SELECT split_part(__method, '.', 2) INTO __method_type;
  END IF;

  RETURN jsonb_build_object(
    'api_type', __api_type,
    'method_type', __method_type,
    'params', __params
  );

END
$$
;