-- at the moment all type checks are performed by hivemind_postgrest_utilities.validate_json_arguments. So it shouldn't be necessary to check again type of passed arguments.

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.parse_argument_from_json;
CREATE FUNCTION hivemind_postgrest_utilities.parse_argument_from_json(_params JSONB, _arg_name TEXT, _exception_on_unset_field BOOLEAN)
RETURNS TEXT
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  IF _params->>_arg_name IS NULL THEN
    IF _exception_on_unset_field THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_missing_required_argument_exception(_arg_name);
    ELSE
      RETURN NULL;
    END IF;
  END IF;

  RETURN _params->>_arg_name;
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.parse_integer_argument_from_json;
CREATE FUNCTION hivemind_postgrest_utilities.parse_integer_argument_from_json(_params JSONB, _arg_name TEXT, _exception_on_unset_field BOOLEAN)
RETURNS INTEGER
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
DECLARE
  _value NUMERIC;
BEGIN
  IF _params->>_arg_name IS NULL THEN
    IF _exception_on_unset_field THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_missing_required_argument_exception(_arg_name);
    ELSE
      RETURN NULL;
    END IF;
  END IF;

  CASE jsonb_typeof(_params->_arg_name)
    WHEN 'string' THEN
      IF _params->>_arg_name ~ '[A-Za-z]' THEN
        RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception(CONCAT('invalid literal for int() with base 10: ''', _params->>_arg_name, ''''));
      ELSIF _params->>_arg_name = '' OR LOWER(_params->>_arg_name) = 'null' THEN
        IF _exception_on_unset_field THEN
          RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_missing_required_argument_exception(_arg_name);
        ELSE
          RETURN NULL;
        END IF;
      ELSE
        _value := (_params->>_arg_name)::NUMERIC;
      END IF;
    WHEN 'null' THEN
      IF _exception_on_unset_field THEN
          RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_missing_required_argument_exception(_arg_name);
      ELSE
        RETURN NULL;
      END IF;
    WHEN 'number' THEN _value := _params->_arg_name;
    WHEN 'array' THEN RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('int() argument must be a string, a bytes-like object or a number, not ''list''');
    ELSE RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('int() argument must be a string, a bytes-like object or a number');
  END CASE;

  IF _value IS NULL OR _value != floor(_value) THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception(FORMAT('Invalid input for integer: parameter %s must be an integer or a float with zero fractional part, but received value ''%s''.', _arg_number, _params->>_arg_number));
  END IF;

  RETURN floor(_value)::INTEGER;
END
$$
;