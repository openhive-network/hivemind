-- Checks that no function in hivemind_endpoints, the schema PostgREST exposes, is
-- VOLATILE. The postgrest-rewriter forwards every REST GET as a POST, and PostgREST runs
-- a POST to a VOLATILE function in a READ WRITE transaction, overriding a role's
-- default_transaction_read_only and keeping it off a hot standby. Then calls the spec
-- function home() as the PostgREST role inside a READ ONLY transaction.
--   psql -X -v ON_ERROR_STOP=1 -f .aidev/endpoint_volatility_check.sql
\set QUIET on

DO $$
DECLARE
    _volatile TEXT;
BEGIN
    SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO _volatile
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'hivemind_endpoints' AND p.provolatile = 'v';
    IF _volatile IS NOT NULL THEN
        RAISE EXCEPTION 'VOLATILE functions in hivemind_endpoints (declare them STABLE): %', _volatile;
    END IF;
END
$$;

BEGIN READ ONLY;
SET LOCAL ROLE hivemind_user;
DO $$
BEGIN
    IF hivemind_endpoints.home()->>'openapi' IS NULL THEN
        RAISE EXCEPTION 'hivemind_endpoints.home() returned no OpenAPI document';
    END IF;
END
$$;
ROLLBACK;

\echo 'hivemind_endpoints: no VOLATILE function; home() answers as hivemind_user in a READ ONLY transaction'
