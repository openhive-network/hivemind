DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.validate_json_arguments;
-- _expected_args has to be a JSON, because it preserve ordering, jsonb does not guarantee order of fields
CREATE FUNCTION hivemind_postgrest_utilities.validate_json_arguments(IN _given_args JSONB, IN _expected_args JSON, IN _min_args_number INT, IN _special_errors_if_type_not_valid JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
DECLARE
  _converted_args_json JSONB DEFAULT '{}'::JSONB;
  _json_is_array BOOLEAN;
  _json_has_call_keyword BOOLEAN DEFAULT False;
  _json_array_len INT;
  _expected_args_keys JSONB;
  _arg_name TEXT;
  _arg_type TEXT;
  _expected_arg_type TEXT;
  _expected_args_number INT;
  _idx INT DEFAULT 0;

BEGIN
  ASSERT json_typeof(_expected_args) = 'object', '_expected_args should be a jsonb object: "{key1: value1, key2: value2 ...}';

  IF jsonb_typeof(_given_args) = 'object' THEN
    IF _given_args ? 'used_call_keyword' THEN
      IF (jsonb_typeof(_given_args->'params') <> 'array') THEN
        RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_invalid_json_format_exception('params not a list');
      END IF;

      _json_is_array = True;
      _json_has_call_keyword = True;
      _given_args = _given_args->'params';
    ELSE
      _json_is_array = False;
    END IF;
  ELSIF jsonb_typeof(_given_args) = 'array' THEN
    _json_is_array = True;
  ELSE
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_invalid_json_format_exception('Invalid JSON parameters format: ' || jsonb_typeof(__params)::text);
  END IF;

  IF _json_is_array THEN
    IF jsonb_typeof(_given_args->0) = 'object' AND jsonb_array_length(_given_args) = 1 THEN
      _json_is_array = False;
      _given_args = _given_args->0;
    ELSE
      ASSERT _min_args_number IS NOT NULL, '_min_args_number should be explicitly specified';
      _expected_args_number = (SELECT COUNT(*) FROM json_object_keys(_expected_args));
      _json_array_len = jsonb_array_length(_given_args);

    
      IF _json_has_call_keyword AND _min_args_number > _json_array_len THEN
        RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_invalid_parameters_array_length_exception((CASE WHEN _min_args_number < _expected_args_number THEN _min_args_number ELSE _expected_args_number END));
      END IF;

      IF _expected_args_number < _json_array_len THEN
        IF _json_has_call_keyword THEN
          RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_invalid_parameters_array_length_exception((CASE WHEN _min_args_number < _expected_args_number THEN _min_args_number ELSE _expected_args_number END));
        ELSE
          RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('too many positional arguments');  
        END IF;
      END IF;
  
      IF _json_array_len > 0 THEN
        FOR _arg_name IN SELECT key FROM json_each_text(_expected_args) LOOP
          _converted_args_json = _converted_args_json || jsonb_build_object(_arg_name, _given_args->_idx);
          _idx = _idx + 1;
        END LOOP;
      END IF;
      _given_args = _converted_args_json;
    END IF;
  END IF;

  SELECT jsonb_agg(key) FROM json_each(_expected_args) INTO _expected_args_keys;

  FOR _arg_name IN SELECT key FROM jsonb_each(_given_args) LOOP
    IF NOT _expected_args_keys ? _arg_name THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_unexpected_keyword_exception(_arg_name);
    END IF;

    _arg_type = jsonb_typeof(_given_args->_arg_name);
    _expected_arg_type = _expected_args->>_arg_name;

    IF (_expected_arg_type = 'number' AND _arg_type NOT IN ('number', 'string','null', 'array')) OR
        (_expected_arg_type <> 'number' AND _arg_type <> _expected_arg_type AND _arg_type <> 'null') THEN
      IF _special_errors_if_type_not_valid IS NOT NULL AND _special_errors_if_type_not_valid ? _arg_name THEN
        RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception(_special_errors_if_type_not_valid->>_arg_name);
      ELSE
        RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('invalid ' || _arg_name || ' type');
      END IF;  
    END IF;
  END LOOP;
  RETURN _given_args;
END
$$
;