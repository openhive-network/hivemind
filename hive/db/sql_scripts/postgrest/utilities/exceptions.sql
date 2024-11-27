DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.raise_exception;
CREATE FUNCTION hivemind_postgrest_utilities.raise_exception(_code INT, _message TEXT, _data TEXT = NULL, _id JSON = NULL)
RETURNS JSONB
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
DECLARE
  error_json_result JSONB;
BEGIN
  IF _data IS NULL THEN
    error_json_result := jsonb_build_object(
      'code', _code,
      'message', _message
    );
  ELSE
    error_json_result := jsonb_build_object(
      'code', _code,
      'message', _message,
      'data', _data
    );
  END IF;
  RAISE EXCEPTION '%', REPLACE(error_json_result::TEXT, ' :', ':');
END
$$;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.raise_method_not_found_exception;
CREATE FUNCTION hivemind_postgrest_utilities.raise_method_not_found_exception(_method_name TEXT)
RETURNS JSONB
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.raise_exception(-32602, 'Invalid parameters', 'unknown method: ' || _method_name);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.raise_api_not_found_exception;
CREATE FUNCTION hivemind_postgrest_utilities.raise_api_not_found_exception(_api_name TEXT)
RETURNS JSONB
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.raise_exception(-32601, 'Api not found ' || _api_name);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.raise_invalid_json_format_exception;
CREATE FUNCTION hivemind_postgrest_utilities.raise_invalid_json_format_exception(_exception_message TEXT)
RETURNS JSONB
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.raise_exception(-32600, _exception_message);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.raise_parameter_validation_exception;
CREATE FUNCTION hivemind_postgrest_utilities.raise_parameter_validation_exception(_exception_message TEXT)
RETURNS JSONB
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.raise_exception(-32602,'Invalid parameters', _exception_message);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.invalid_account_exception;
CREATE FUNCTION hivemind_postgrest_utilities.invalid_account_exception(_exception_message TEXT)
RETURNS JSONB
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.raise_exception(-32602,'Invalid parameters', _exception_message);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.raise_post_deleted_exception;
CREATE FUNCTION hivemind_postgrest_utilities.raise_post_deleted_exception(in _author TEXT, in _permlink TEXT, in _times INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  IF _author IS NULL THEN
    _author = '';
  END IF;
  IF _permlink IS NULL THEN
    _permlink = '';
  END IF;
  RETURN hivemind_postgrest_utilities.raise_exception(-31999, 'Invalid parameters', 'Post ' || _author || '/' || _permlink || ' was deleted ' || _times || ' time(s)');
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.raise_non_existing_post_exception;
CREATE FUNCTION hivemind_postgrest_utilities.raise_non_existing_post_exception(in _author TEXT, in _permlink TEXT)
RETURNS JSONB
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  IF _author IS NULL THEN
    _author = '';
  END IF;
  IF _permlink IS NULL THEN
    _permlink = '';
  END IF;
  RETURN hivemind_postgrest_utilities.raise_exception(-32602, 'Invalid parameters', 'Post ' || _author::TEXT || '/' || _permlink::TEXT || ' does not exist');
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.raise_invalid_parameters_array_length_exception;
CREATE FUNCTION hivemind_postgrest_utilities.raise_invalid_parameters_array_length_exception(in _expected_count INTEGER)
RETURNS JSONB
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.raise_exception(-32602, 'Invalid parameters','expected ' || _expected_count || ' params');
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.raise_unexpected_keyword_exception;
CREATE FUNCTION hivemind_postgrest_utilities.raise_unexpected_keyword_exception(_arg_name TEXT)
RETURNS JSONB
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.raise_exception(-32602, 'Invalid parameters', 'got an unexpected keyword argument ''' || _arg_name || '''');
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.raise_missing_required_argument_exception;
CREATE FUNCTION hivemind_postgrest_utilities.raise_missing_required_argument_exception(_arg_name TEXT)
RETURNS JSONB
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.raise_exception(-32602, 'Invalid parameters', 'missing a required argument: ''' || _arg_name || '''');
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.raise_invalid_permlink_exception;
CREATE FUNCTION hivemind_postgrest_utilities.raise_invalid_permlink_exception(_exception_message TEXT)
RETURNS JSONB
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.raise_exception(-32602, 'Invalid parameters', _exception_message);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.raise_uint_exception;
CREATE FUNCTION hivemind_postgrest_utilities.raise_uint_exception(_id JSON)
RETURNS JSONB
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.raise_exception(-32000, 'Parse Error:Couldn''t parse uint64_t', NULL, _id);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.raise_operation_param_exception;
CREATE FUNCTION hivemind_postgrest_utilities.raise_operation_param_exception(_exception_message TEXT, _id JSON)
RETURNS JSONB
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.raise_exception(-32602,'Invalid parameters',_exception_message, _id);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.raise_category_not_exists_exception;
CREATE FUNCTION hivemind_postgrest_utilities.raise_category_not_exists_exception(_category_name TEXT)
RETURNS JSONB
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.raise_exception(-32602, 'Invalid parameters', 'Category ' || _category_name || ' does not exist');
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.raise_community_exception;
CREATE FUNCTION hivemind_postgrest_utilities.raise_community_exception(_exception_message TEXT)
RETURNS JSONB
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.raise_exception(-32602,'Invalid parameters', _exception_message);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.raise_extra_arg;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.raise_extra_arg(_arg_name TEXT, _id JSON)
RETURNS JSONB
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.raise_exception(-32602, 'Invalid parameters', format('got an unexpected keyword argument ''%s''', _arg_name), _id);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.raise_int_exception;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.raise_int_exception(_id JSON)
RETURNS JSONB
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.raise_exception(-32000, 'Parse Error:Couldn''t parse int64_t', NULL, _id, TRUE);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.raise_account_exception;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.raise_account_exception(_id JSON)
RETURNS JSONB
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.raise_exception(-32602,'Invalid parameters','invalid account name type', _id);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.raise_invalid_array_exception;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.raise_invalid_array_exception(_id JSON)
RETURNS JSONB
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.raise_exception(-32602,'Invalid parameters','too many positional arguments', _id);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.raise_tag_not_exists_exception;
CREATE FUNCTION hivemind_postgrest_utilities.raise_tag_not_exists_exception(IN _tag TEXT)
RETURNS JSONB
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.raise_exception(-32602, 'Invalid parameters', 'Tag ' || _tag || ' does not exist');
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.invalid_notify_type_id_exception;
CREATE FUNCTION hivemind_postgrest_utilities.invalid_notify_type_id_exception(_exception_message TEXT)
RETURNS JSONB
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.raise_exception(-32602,'Invalid parameters', _exception_message);
END
$$
;