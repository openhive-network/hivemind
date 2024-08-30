DROP FUNCTION IF EXISTS hivemind_utilities.validate_json_parameters;
CREATE OR REPLACE FUNCTION hivemind_utilities.validate_json_parameters(IN _json_type TEXT, IN _params JSON, IN _expected_params_for_object JSON, IN _expected_json_array_min_len INT, IN _expected_json_array_max_len INT, IN _expected_json_types_for_array JSON)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
passed_arg_key TEXT;
passed_type_to_check TEXT;
expected_type_to_check TEXT;
array_idx INT := 0;
BEGIN
  IF _json_type = 'object' THEN
    FOR passed_arg_key IN SELECT key FROM json_each(_params) LOOP
      IF _expected_params_for_object->passed_arg_key IS NOT NULL THEN
        passed_type_to_check = json_typeof(_params->passed_arg_key);
        expected_type_to_check = _expected_params_for_object->>passed_arg_key;
        IF passed_type_to_check <> expected_type_to_check THEN
          RAISE EXCEPTION '%', hivemind_utilities.raise_parameter_validation_exception('Invalid type for parameter: ' || passed_arg_key || ' which is type of: ' || passed_type_to_check || ', expected type: ' || expected_type_to_check);
        END IF;
      ELSE
        RAISE EXCEPTION '%', hivemind_utilities.raise_unexpected_keyword_exception(passed_arg_key);
      END IF;
    END LOOP;
  ELSEIF _json_type = 'array' THEN
    IF json_array_length(_params) > _expected_json_array_max_len THEN
      RAISE EXCEPTION '%', hivemind_utilities.raise_invalid_array_exception(True);
    ELSEIF json_array_length(_params) < _expected_json_array_min_len THEN
      RAISE EXCEPTION '%', hivemind_utilities.raise_invalid_array_exception(True);
    ELSE
      FOR array_idx IN 0.._expected_json_array_max_len-1 LOOP
        IF _params->array_idx IS NOT NULL THEN
          expected_type_to_check = _expected_json_types_for_array->>array_idx;
          passed_type_to_check = json_typeof(_params->array_idx);
          IF passed_type_to_check <> expected_type_to_check THEN
            RAISE EXCEPTION '%', hivemind_utilities.raise_parameter_validation_exception('Invalid type at position ' || array_idx || ': ' || passed_type_to_check || ', expected type: ' || expected_type_to_check);
          END IF;
        -- not all parameters are required, so return without an error
        ELSE
          RETURN NULL;
        END IF;
      END LOOP;
    END IF;
  ELSE
    RAISE EXCEPTION '%', hivemind_utilities.raise_invalid_json_format_exception('Invalid JSON format: ' || _json_type);
  END IF;
  RETURN NULL;
END
$$
;