-- REST endpoints that mirror a JSON-RPC method call it through dispatch, so both
-- surfaces run the same code, and report its errors as plain PostgREST errors.

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.raise_rest_exception;
-- Re-raises a JSON-RPC error (the SQLERRM of a raise_exception*() call) with its `message`
-- as the message and, when `data` is a string, `data` as the detail. Object `data` (the
-- hived-style assert payload) is dropped: it carries a timestamp. PostgREST answers 400.
CREATE FUNCTION hivemind_postgrest_utilities.raise_rest_exception(_json_rpc_error TEXT)
RETURNS VOID
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
DECLARE
  _error JSONB;
BEGIN
  IF NOT (_json_rpc_error IS JSON OBJECT) THEN
    RAISE EXCEPTION '%', _json_rpc_error;
  END IF;

  _error = _json_rpc_error::JSONB;
  IF jsonb_typeof(_error->'data') = 'string' THEN
    RAISE EXCEPTION '%', _error->>'message' USING DETAIL = _error->>'data';
  END IF;
  RAISE EXCEPTION '%', _error->>'message';
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.rest_json_rpc_call;
-- Calls the JSON-RPC method `_api_type`.`_method_type` with the named arguments in `_params`.
-- Null arguments are left out, as an absent REST parameter means an absent JSON-RPC argument.
CREATE FUNCTION hivemind_postgrest_utilities.rest_json_rpc_call(_api_type TEXT, _method_type TEXT, _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.dispatch(_api_type, _method_type, jsonb_strip_nulls(_params));
EXCEPTION
  WHEN raise_exception THEN
    PERFORM hivemind_postgrest_utilities.raise_rest_exception(SQLERRM);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.rest_json_rpc_rows;
-- rest_json_rpc_call() for a method that returns a list: one row per element, in list order,
-- so that PostgREST applies the `limit` and `offset` of a GET request to the list.
CREATE FUNCTION hivemind_postgrest_utilities.rest_json_rpc_rows(_api_type TEXT, _method_type TEXT, _params JSONB)
RETURNS SETOF JSONB
LANGUAGE 'sql'
STABLE
AS
$$
  SELECT element.value
  FROM jsonb_array_elements(hivemind_postgrest_utilities.rest_json_rpc_call(_api_type, _method_type, _params)) WITH ORDINALITY AS element(value, ord)
  ORDER BY element.ord
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.rest_page_limit;
-- The page size a list endpoint asks its JSON-RPC method for: `_limit` clamped to [1, `_max`],
-- or `_max` when absent. A GET request cannot pass `limit` to the function (PostgREST reserves it),
-- so such a request gets the largest page and PostgREST cuts it to its `limit`; keyset pages are
-- prefix-consistent, so that equals the method's page of that size.
CREATE FUNCTION hivemind_postgrest_utilities.rest_page_limit(_limit INT, _max INT)
RETURNS INT
LANGUAGE 'sql'
IMMUTABLE
AS
$$
  SELECT GREATEST(LEAST(COALESCE(_limit, _max), _max), 1)
$$
;
