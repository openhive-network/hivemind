-- condenser_api.get_followers answers the same whether it walks hive_accounts by name or
-- reads every follower, through hivemind_endpoints.home. Seeds its own accounts and follows
-- in a transaction it rolls back, so it runs on any installed hivemind schema, including an
-- empty chain:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/condenser_get_followers_walk.sql
--
-- The walk is taken when twice its expected length, 2 * limit * accounts / followers, is
-- under the follower count, and gives up after that many accounts. With followers set to
-- 2 * accounts the budget is exactly the limit, and the accounts right after the start,
-- cfw-start-01 onwards, are all followers, so the walk fills the page. With followers 0
-- the same call reads every follower instead. A follower before the start and the start
-- itself, also a follower, must stay out of both answers.

\set ON_ERROR_STOP 1
BEGIN;

INSERT INTO hivemind_app.hive_accounts (name, created_at)
SELECT name, '2016-06-01'
FROM unnest(ARRAY['cfw-account', 'cfw-a-follower', 'cfw-start']) AS name;
INSERT INTO hivemind_app.hive_accounts (name, created_at)
SELECT 'cfw-start-' || lpad(i::TEXT, 2, '0'), '2016-06-01' FROM generate_series(1, 12) i;

INSERT INTO hivemind_app.follows (follower, following, block_num)
SELECT ha.id, (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'cfw-account'), 1
FROM hivemind_app.hive_accounts ha
WHERE ha.name LIKE 'cfw-%' AND ha.name <> 'cfw-account';

DO $$
DECLARE
  _accounts FLOAT8 := (SELECT GREATEST(c.reltuples, 1) FROM pg_class c WHERE c.oid = 'hivemind_app.hive_accounts'::regclass);
  _limit INT := LEAST(10, floor(_accounts))::INT;
  _expected JSONB := (SELECT jsonb_agg('cfw-start-' || lpad(i::TEXT, 2, '0') ORDER BY i) FROM generate_series(1, _limit) i);
  _followers FLOAT8;
  _r JSONB;
BEGIN
  FOREACH _followers IN ARRAY ARRAY[2 * _accounts, 0] LOOP
    UPDATE hivemind_app.hive_accounts SET followers = _followers WHERE name = 'cfw-account';

    _r = hivemind_endpoints.home(json_build_object('jsonrpc', '2.0', 'id', 1, 'method', 'condenser_api.get_followers',
      'params', json_build_array('cfw-account', 'cfw-start', 'blog', _limit)))::JSONB;
    IF jsonb_path_query_array(_r, '$.result[*].follower') IS DISTINCT FROM _expected THEN
      RAISE EXCEPTION 'followers % limit %: expected %, got %', _followers, _limit, _expected, _r;
    END IF;
    IF _r->'result'->0 IS DISTINCT FROM jsonb_build_object('follower', 'cfw-start-01', 'following', 'cfw-account', 'what', '["blog"]'::JSONB) THEN
      RAISE EXCEPTION 'followers % limit %: unexpected entry %', _followers, _limit, _r->'result'->0;
    END IF;

    -- Fewer followers remain after cfw-start-11 than the limit asks for: the walk cannot fill the page.
    _r = hivemind_endpoints.home(json_build_object('jsonrpc', '2.0', 'id', 1, 'method', 'condenser_api.get_followers',
      'params', json_build_array('cfw-account', 'cfw-start-11', 'blog', 5)))::JSONB;
    IF jsonb_path_query_array(_r, '$.result[*].follower') IS DISTINCT FROM '["cfw-start-12"]'::JSONB THEN
      RAISE EXCEPTION 'followers % after cfw-start-11: expected ["cfw-start-12"], got %', _followers, _r;
    END IF;

    _r = hivemind_endpoints.home(json_build_object('jsonrpc', '2.0', 'id', 1, 'method', 'condenser_api.get_followers',
      'params', json_build_array('cfw-account', '', 'blog', 1000)))::JSONB;
    IF jsonb_array_length(_r->'result') <> 14 OR NOT (_r->'result') @> '[{"follower": "cfw-a-follower"}, {"follower": "cfw-start"}]' THEN
      RAISE EXCEPTION 'followers % from the beginning: expected all 14 seeded followers, got %', _followers, _r;
    END IF;
  END LOOP;
END
$$;

ROLLBACK;
