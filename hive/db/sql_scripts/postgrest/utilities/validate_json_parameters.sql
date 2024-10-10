DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.validate_json_parameters;
CREATE FUNCTION hivemind_postgrest_utilities.validate_json_parameters(IN _json_is_object BOOLEAN, IN _params JSONB, IN _expected_params_names TEXT[], IN _expected_params_types TEXT[], IN _min_parameters_array_len INT DEFAULT NULL)
RETURNS JSONB
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
DECLARE
passed_arg_key TEXT;
passed_type_to_check TEXT;
expected_type_to_check TEXT;
array_idx INT;
expected_array_len INT;
BEGIN
  IF _json_is_object THEN
    -- There is a case, when we expect params as an object, but no parameters are actually passed and we have an empty json array.
    -- In that case, we should don't check anything (because no params are passed). Otherwise, we should investigate and find solution.
    IF jsonb_typeof(_params) = 'array' THEN
      IF jsonb_array_length(_params) <> 0 THEN
        RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_invalid_json_format_exception('Invalid JSON-RPC - validate_json_parameters');
      ELSE
        RETURN NULL;
      END IF;
    END IF;
    FOR passed_arg_key IN SELECT key FROM jsonb_each(_params) LOOP
      array_idx = array_position(_expected_params_names, passed_arg_key);
      IF array_idx IS NOT NULL THEN
        passed_type_to_check = jsonb_typeof(_params->passed_arg_key);
        expected_type_to_check = _expected_params_types[array_idx];
        IF (expected_type_to_check = 'number' AND passed_type_to_check NOT IN ('number', 'string','null')) OR (expected_type_to_check <> 'number' AND passed_type_to_check <> expected_type_to_check AND passed_type_to_check <> 'null') THEN
          RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('invalid ' || passed_arg_key || ' type');
        END IF;
      ELSE
        RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_unexpected_keyword_exception(passed_arg_key);
      END IF;
    END LOOP;
  ELSE
    expected_array_len = CARDINALITY(_expected_params_types);
    IF (_min_parameters_array_len IS NOT NULL AND (_min_parameters_array_len > jsonb_array_length(_params) OR jsonb_array_length(_params) < jsonb_array_length(_params)))
      OR (_min_parameters_array_len IS NULL AND jsonb_array_length(_params) <> expected_array_len) THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_invalid_parameters_array_length_exception(expected_array_len, jsonb_array_length(_params));
    ELSE
      FOR array_idx IN 1..expected_array_len-1 LOOP
        IF _params->array_idx IS NOT NULL THEN
          expected_type_to_check = _expected_params_types[array_idx];
          passed_type_to_check = jsonb_typeof(_params->(array_idx-1));
          IF (expected_type_to_check = 'number' AND passed_type_to_check NOT IN ('number', 'string','null')) OR (expected_type_to_check <> 'number' AND passed_type_to_check <> expected_type_to_check AND passed_type_to_check <> 'null') THEN
            RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('invalid ' || _expected_params_names[array_idx] || ' type');
          END IF;
        -- not all parameters are required, so return without an error
        ELSE
          RETURN NULL;
        END IF;
      END LOOP;
    END IF;
  END IF;
  RETURN NULL;
END
$$
;