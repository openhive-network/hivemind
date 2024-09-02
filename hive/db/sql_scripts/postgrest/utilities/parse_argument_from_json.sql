-- at the moment all type checks are performed by hivemind_utilities.validate_json_parameters. So it shouldn't be necessary to check again type of passed parameter.

DROP FUNCTION IF EXISTS hivemind_utilities.parse_string_argument_from_json;
CREATE FUNCTION hivemind_utilities.parse_string_argument_from_json(_params JSON, _json_is_object BOOLEAN, _arg_name TEXT, _arg_number INT, _exception_on_unset_field BOOLEAN)
RETURNS TEXT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  IF _exception_on_unset_field THEN
    IF _json_is_object THEN
      IF _params->>_arg_name IS NULL THEN
        RAISE EXCEPTION '%', hivemind_utilities.raise_missing_required_argument_exception(_arg_name);
      ELSE
        RETURN _params->>_arg_name;
      END IF;
    ELSE
      IF _params->>_arg_number IS NULL THEN
        RAISE EXCEPTION '%', hivemind_utilities.raise_missing_required_argument_exception(_arg_name);
      ELSE
        RETURN _params->>_arg_number;
      END IF;
    END IF;
  ELSE
    IF _json_is_object THEN
      IF _params->>_arg_name IS NULL THEN
        RETURN NULL;
      ELSE
        RETURN _params->>_arg_name;
      END IF;
    ELSE
      IF _params->>_arg_number IS NULL THEN
        RETURN NULL;
      ELSE
        RETURN _params->>_arg_number;
      END IF;
    END IF;
  END IF;
END
$$
;

DROP FUNCTION IF EXISTS hivemind_utilities.parse_integer_argument_from_json;
CREATE FUNCTION hivemind_utilities.parse_integer_argument_from_json(_params JSON, _json_is_object BOOLEAN, _arg_name TEXT, _arg_number INT, _exception_on_unset_field BOOLEAN)
RETURNS INTEGER
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  IF _exception_on_unset_field THEN
    IF _json_is_object THEN
      IF _params->>_arg_name IS NULL THEN
        RAISE EXCEPTION '%', hivemind_utilities.raise_missing_required_argument_exception(_arg_name);
      ELSE
        RETURN _params->>_arg_name;
      END IF;
    ELSE
      IF _params->>_arg_number IS NULL THEN
        RAISE EXCEPTION '%', hivemind_utilities.raise_missing_required_argument_exception(_arg_name);
      ELSE
        RETURN _params->>_arg_number;
      END IF;
    END IF;
  ELSE
    IF _json_is_object THEN
      IF _params->>_arg_name IS NULL THEN
        RETURN NULL;
      ELSE
        RETURN _params->>_arg_name;
      END IF;
    ELSE
      IF _params->>_arg_number IS NULL THEN
        RETURN NULL;
      ELSE
        RETURN _params->>_arg_number;
      END IF;
    END IF;
  END IF;
END
$$
;