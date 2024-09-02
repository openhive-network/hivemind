DROP FUNCTION IF EXISTS hivemind_utilities.raise_exception;
CREATE OR REPLACE FUNCTION hivemind_utilities.raise_exception(_code INT, _message TEXT, _data TEXT = NULL, _id JSON = NULL)
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
    CASE WHEN _data IS NULL THEN
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
    'id', _id -- this should be updated to right number in hivemind_endpoints.home when exception is caught
  ) error_json;
END
$$
;

DROP FUNCTION IF EXISTS hivemind_utilities.raise_method_not_found_exception;
CREATE OR REPLACE FUNCTION hivemind_utilities.raise_method_not_found_exception(_method_name TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_utilities.raise_exception(-32601, 'Method not found ' || _method_name);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_utilities.raise_invalid_json_format_exception;
CREATE OR REPLACE FUNCTION hivemind_utilities.raise_invalid_json_format_exception(_exception_message TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_utilities.raise_exception(-32600, _exception_message);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_utilities.raise_parameter_validation_exception;
CREATE OR REPLACE FUNCTION hivemind_utilities.raise_parameter_validation_exception(_exception_message TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_utilities.raise_exception(-32602,'Invalid parameters', _exception_message);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_utilities.invalid_account_exception;
CREATE OR REPLACE FUNCTION hivemind_utilities.invalid_account_exception(_exception_message TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_utilities.raise_exception(-32602,'Invalid parameters', _exception_message);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_utilities.raise_post_deleted_exception;
CREATE OR REPLACE FUNCTION hivemind_utilities.raise_post_deleted_exception(in _author TEXT, in _permlink TEXT, in _times INT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_utilities.raise_exception(-31999, 'Invalid parameters', 'Post ' || _author || '/' || _permlink || ' was deleted ' || _times || ' time(s)');
END
$$
;

DROP FUNCTION IF EXISTS hivemind_utilities.raise_non_existing_post_exception;
CREATE OR REPLACE FUNCTION hivemind_utilities.raise_non_existing_post_exception(in _author TEXT, in _permlink TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_utilities.raise_exception(-32602, 'Invalid parameters', 'Post ' || _author || '/' || _permlink || ' does not exist');
END
$$
;

DROP FUNCTION IF EXISTS hivemind_utilities.raise_invalid_array_exception;
CREATE OR REPLACE FUNCTION hivemind_utilities.raise_invalid_array_exception(in too_many BOOLEAN)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  IF too_many THEN
    RETURN hivemind_utilities.raise_exception(-32602,'Invalid parameters','too many positional arguments');
  ELSE
    RETURN hivemind_utilities.raise_exception(-32602,'Invalid parameters','too few positional arguments');
  END IF;
END
$$
;

DROP FUNCTION IF EXISTS hivemind_utilities.raise_unexpected_keyword_exception;
CREATE OR REPLACE FUNCTION hivemind_utilities.raise_unexpected_keyword_exception(_arg_name TEXT)
RETURNS TEXT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_utilities.raise_exception(-32602, 'Invalid parameters', 'got an unexpected keyword argument ' || _arg_name);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_utilities.raise_missing_required_argument_exception;
CREATE OR REPLACE FUNCTION hivemind_utilities.raise_missing_required_argument_exception(_arg_name TEXT)
RETURNS TEXT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_utilities.raise_exception(-32602, 'Invalid parameters', 'missing a required argument: ''' || _arg_name || '''');
END
$$
;

DROP FUNCTION IF EXISTS hivemind_utilities.raise_invalid_permlink_exception;
CREATE OR REPLACE FUNCTION hivemind_utilities.raise_invalid_permlink_exception(_exception_message TEXT)
RETURNS TEXT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_utilities.raise_exception(-32602, 'Invalid parameters', _exception_message);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_utilities.raise_uint_exception;
CREATE OR REPLACE FUNCTION hivemind_utilities.raise_uint_exception(_id JSON)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_utilities.raise_exception(-32000, 'Parse Error:Couldn''t parse uint64_t', NULL, _id);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_utilities.raise_operation_param_exception;
CREATE OR REPLACE FUNCTION hivemind_utilities.raise_operation_param_exception(_exception_message TEXT, _id JSON)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_utilities.raise_exception(-32602,'Invalid parameters',_exception_message, NULL, _id);
END
$$
;