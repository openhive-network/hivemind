DROP FUNCTION IF EXISTS hivemind_utilities.validate_json_parameters;
CREATE OR REPLACE FUNCTION hivemind_utilities.validate_json_parameters(IN _json_is_object BOOLEAN, IN _method_is_call BOOLEAN, IN _params JSON, IN _expected_params_names TEXT[], IN _expected_params_types TEXT[])
RETURNS JSON
LANGUAGE 'plpgsql'
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
    IF json_typeof(_params) = 'array' THEN
      IF json_array_length(_params) <> 0 THEN
        RAISE EXCEPTION '%', hivemind_utilities.raise_invalid_json_format_exception('Invalid JSON-RPC - validate_json_parameters');
      ELSE
        RETURN NULL;
      END IF;
    END IF;
    FOR passed_arg_key IN SELECT key FROM json_each(_params) LOOP
      array_idx = array_position(_expected_params_names, passed_arg_key);
      IF array_idx IS NOT NULL THEN
        passed_type_to_check = json_typeof(_params->passed_arg_key);
        expected_type_to_check = _expected_params_types[array_idx];
        IF passed_type_to_check <> expected_type_to_check THEN
          RAISE EXCEPTION '%', hivemind_utilities.raise_parameter_validation_exception('invalid ' || passed_arg_key || ' type');
        END IF;
      ELSE
        RAISE EXCEPTION '%', hivemind_utilities.raise_unexpected_keyword_exception(passed_arg_key);
      END IF;
    END LOOP;
  ELSE
    expected_array_len = array_length(_expected_params_types, 1);
    IF json_array_length(_params) <> expected_array_len THEN
      RAISE EXCEPTION '%', hivemind_utilities.raise_invalid_parameters_array_length_exception(expected_array_len, json_array_length(_params), _method_is_call);
    ELSE
      FOR array_idx IN 1..expected_array_len-1 LOOP
        IF _params->array_idx IS NOT NULL THEN
          expected_type_to_check = _expected_params_types[array_idx];
          passed_type_to_check = json_typeof(_params->(array_idx-1));
          IF passed_type_to_check <> expected_type_to_check THEN
            RAISE EXCEPTION '%', hivemind_utilities.raise_parameter_validation_exception('invalid ' || _expected_params_names[array_idx] || ' type');
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