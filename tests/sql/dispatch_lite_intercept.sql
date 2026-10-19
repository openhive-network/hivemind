-- The optional lite_posts intercept in hivemind_postgrest_utilities.dispatch, against a
-- stub lite_posts.intercept created in a transaction it rolls back (dropping the stub),
-- so it runs on any installed hivemind schema:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/dispatch_lite_intercept.sql
--
-- The stub answers ('lite', 'probe') and returns NULL for everything else.

\set ON_ERROR_STOP 1
BEGIN;

CREATE SCHEMA lite_posts;
CREATE FUNCTION lite_posts.intercept(IN __api_type TEXT, IN __method_type TEXT, IN __params JSONB)
RETURNS JSONB
LANGUAGE 'sql'
STABLE
AS
$$
  SELECT CASE WHEN __api_type = 'lite' AND __method_type = 'probe' THEN '{"lite": "probe"}'::JSONB END
$$
;

DO $$
DECLARE
  _stock JSONB;
  _r JSONB;
  _err JSONB;
BEGIN
  PERFORM set_config('hivemind.lite_intercept', '', true);
  _stock = hivemind_postgrest_utilities.dispatch('bridge', 'get_trending_topics', '{}');

  PERFORM set_config('hivemind.lite_intercept', 'on', true);
  _r = hivemind_postgrest_utilities.dispatch('lite', 'probe', '{}');
  IF _r IS DISTINCT FROM '{"lite": "probe"}'::JSONB THEN
    RAISE EXCEPTION 'intercept on: lite.probe returned %, expected the stub object', _r;
  END IF;
  _r = hivemind_postgrest_utilities.dispatch('bridge', 'get_trending_topics', '{}');
  IF _r IS DISTINCT FROM _stock THEN
    RAISE EXCEPTION 'intercept on: bridge.get_trending_topics returned %, expected the stock %', _r, _stock;
  END IF;
  _err = hivemind_endpoints.home('{"jsonrpc": "2.0", "id": 1, "method": "lite.other", "params": {}}')::JSONB;
  IF _err->'error'->>'message' IS DISTINCT FROM 'Api not found lite' THEN
    RAISE EXCEPTION 'intercept on: unhandled lite.other returned %, expected Api not found', _err;
  END IF;

  PERFORM set_config('hivemind.lite_intercept', '', true);
  _err = hivemind_endpoints.home('{"jsonrpc": "2.0", "id": 1, "method": "lite.probe", "params": {}}')::JSONB;
  IF _err->'error'->>'code' IS DISTINCT FROM '-32601' OR _err->'error'->>'message' IS DISTINCT FROM 'Api not found lite' THEN
    RAISE EXCEPTION 'intercept off: lite.probe returned %, expected Api not found', _err;
  END IF;
END
$$;

ROLLBACK;
