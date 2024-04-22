DROP FUNCTION IF EXISTS hivemind_helpers.raise_exception;
CREATE OR REPLACE FUNCTION hivemind_helpers.raise_exception(_code INT, _message TEXT, _data TEXT = NULL, _id JSON = NULL, _no_data BOOLEAN = FALSE)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN
    REPLACE(error_json::TEXT, ' :', ':')
  FROM json_build_object(
    'jsonrpc', '2.0',
    'error',
    CASE WHEN _no_data IS TRUE THEN
      json_build_object(
        'code', _code,
        'message', _message
      )
    ELSE
      json_build_object(
        'code', _code,
        'message', _message,
        'data', _data
      )
    END,
    'id', _id
  ) error_json;
END
$$
;

DROP FUNCTION IF EXISTS hivemind_helpers.raise_missing_arg;
CREATE OR REPLACE FUNCTION hivemind_helpers.raise_missing_arg(_arg_name TEXT, _id JSON)
RETURNS TEXT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_helpers.raise_exception(-32602, 'Invalid parameters', format('missing a required argument: ''%s''', _arg_name), _id);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_helpers.raise_extra_arg;
CREATE OR REPLACE FUNCTION hivemind_helpers.raise_extra_arg(_arg_name TEXT, _id JSON)
RETURNS TEXT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_helpers.raise_exception(-32602, 'Invalid parameters', format('got an unexpected keyword argument ''%s''', _arg_name), _id);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_helpers.raise_operation_param;
CREATE OR REPLACE FUNCTION hivemind_helpers.raise_operation_param(_exception_message TEXT,_id JSON)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_helpers.raise_exception(-32602,'Invalid parameters',_exception_message, _id);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_helpers.raise_uint_exception;
CREATE OR REPLACE FUNCTION hivemind_helpers.raise_uint_exception(_id JSON)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_helpers.raise_exception(-32000, 'Parse Error:Couldn''t parse uint64_t', NULL, _id, TRUE);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_helpers.raise_int_exception;
CREATE OR REPLACE FUNCTION hivemind_helpers.raise_int_exception(_id JSON)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_helpers.raise_exception(-32000, 'Parse Error:Couldn''t parse int64_t', NULL, _id, TRUE);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_helpers.raise_account_exception;
CREATE OR REPLACE FUNCTION hivemind_helpers.raise_account_exception(_id JSON)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_helpers.raise_exception(-32602,'Invalid parameters','invalid account name type', _id);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_helpers.raise_community_exception;
CREATE OR REPLACE FUNCTION hivemind_helpers.raise_community_exception(_id JSON)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_helpers.raise_exception(-32602,'Invalid parameters','given community name is not valid', _id);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_helpers.raise_invalid_array_exception;
CREATE OR REPLACE FUNCTION hivemind_helpers.raise_invalid_array_exception(_id JSON)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_helpers.raise_exception(-32602,'Invalid parameters','too many positional arguments', _id);
END
$$
;
