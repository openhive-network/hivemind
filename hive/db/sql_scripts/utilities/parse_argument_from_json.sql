DROP FUNCTION IF EXISTS hivemind_utilities.parse_argument_from_json;
CREATE FUNCTION hivemind_utilities.parse_argument_from_json(_params JSON, _json_type TEXT, _arg_name TEXT, _arg_number INT, _exception_on_unset_field BOOLEAN, _is_bool BOOLEAN = FALSE)
RETURNS TEXT
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __param TEXT;
BEGIN
  IF _exception_on_unset_field AND (_json_type = 'object' AND _params->>_arg_name IS NULL OR _json_type = 'array' AND _params->>_arg_number IS NULL) THEN
      RAISE EXCEPTION '%', hivemind_utilities.raise_missing_required_argument_exception(_arg_name);
  END IF;

  SELECT CASE WHEN _json_type = 'object' THEN
    _params->>_arg_name
  ELSE
    _params->>_arg_number
  END INTO __param;

  -- TODO: this is done to replicate behaviour of HAfAH python, might remove
  IF _is_bool IS TRUE AND __param ~ '([A-Z].+)' THEN
    RAISE invalid_text_representation;
  ELSE
    RETURN __param;
  END IF;
END
$$
;