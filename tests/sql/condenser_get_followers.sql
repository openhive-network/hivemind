-- condenser_api.get_followers through hivemind_endpoints.home pages an account's followers in
-- hive_accounts.name ("C") order from an exclusive start, reading follows.follower_name, which
-- the follow write path fills. Seeds its own accounts and follows in a transaction it rolls
-- back, so it runs on any installed hivemind schema, including an empty chain:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/condenser_get_followers.sql
--
-- The follower names differ only in '-', '.' and digits, which "C" orders by byte value and a
-- linguistic collation would not. cfw-late follows only after the first pages were read and
-- must then appear in its name's place. A muted account must stay out of the blog list.

\set ON_ERROR_STOP 1
BEGIN;

INSERT INTO hivemind_app.hive_accounts (name, created_at)
SELECT name, '2016-06-01'
FROM unnest(ARRAY['cfw-account', 'cfw.abc', 'cfw-b', 'cfw-a1', 'cfw-a-1', 'cfw-start', 'cfw-late', 'cfw-muter']) AS name;
INSERT INTO hivemind_app.hive_accounts (name, created_at)
SELECT 'cfw-start-' || lpad(i::TEXT, 2, '0'), '2016-06-01' FROM generate_series(1, 12) i;

SELECT hivemind_app.insert_follows(ARRAY(
  SELECT ROW(ha.id, (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'cfw-account'), 1)::hivemind_app.follow_ids
  FROM hivemind_app.hive_accounts ha
  WHERE ha.name LIKE 'cfw%' AND ha.name NOT IN ('cfw-account', 'cfw-late', 'cfw-muter')
));
INSERT INTO hivemind_app.muted (follower, following, block_num)
SELECT (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'cfw-muter'), (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'cfw-account'), 1;

CREATE FUNCTION pg_temp.cfw_followers(_start TEXT, _limit INT, _type TEXT DEFAULT 'blog') RETURNS JSONB LANGUAGE sql AS $$
  SELECT hivemind_endpoints.home(json_build_object('jsonrpc', '2.0', 'id', 1, 'method', 'condenser_api.get_followers',
    'params', json_build_array('cfw-account', _start, _type, _limit)))::JSONB
$$;

DO $$
DECLARE
  _all JSONB := '["cfw-a-1", "cfw-a1", "cfw-b", "cfw-start", "cfw-start-01", "cfw-start-02", "cfw-start-03", "cfw-start-04",
                  "cfw-start-05", "cfw-start-06", "cfw-start-07", "cfw-start-08", "cfw-start-09", "cfw-start-10", "cfw-start-11",
                  "cfw-start-12", "cfw.abc"]';
  _r JSONB;
  _paged JSONB := '[]';
  _start TEXT := '';
BEGIN
  IF EXISTS (
    SELECT NULL FROM hivemind_app.follows f JOIN hivemind_app.hive_accounts ha ON ha.id = f.follower
    WHERE ha.name LIKE 'cfw%' AND f.follower_name IS DISTINCT FROM ha.name
  ) THEN
    RAISE EXCEPTION 'follows.follower_name differs from hive_accounts.name';
  END IF;

  _r = pg_temp.cfw_followers('', 1000);
  IF jsonb_path_query_array(_r, '$.result[*].follower') IS DISTINCT FROM _all THEN
    RAISE EXCEPTION 'from the beginning: expected %, got %', _all, _r;
  END IF;
  IF _r->'result'->0 IS DISTINCT FROM jsonb_build_object('follower', 'cfw-a-1', 'following', 'cfw-account', 'what', '["blog"]'::JSONB) THEN
    RAISE EXCEPTION 'unexpected entry %', _r->'result'->0;
  END IF;

  _r = pg_temp.cfw_followers('cfw-start', 3);
  IF jsonb_path_query_array(_r, '$.result[*].follower') IS DISTINCT FROM '["cfw-start-01", "cfw-start-02", "cfw-start-03"]'::JSONB THEN
    RAISE EXCEPTION 'after cfw-start: expected the next 3, got %', _r;
  END IF;

  _r = pg_temp.cfw_followers('cfw-start-12', 5);
  IF jsonb_path_query_array(_r, '$.result[*].follower') IS DISTINCT FROM '["cfw.abc"]'::JSONB THEN
    RAISE EXCEPTION 'after cfw-start-12: expected ["cfw.abc"], got %', _r;
  END IF;

  _r = pg_temp.cfw_followers('cfw.abc', 5);
  IF _r->'result' IS DISTINCT FROM '[]'::JSONB THEN
    RAISE EXCEPTION 'after the last follower: expected [], got %', _r;
  END IF;

  LOOP
    _r = pg_temp.cfw_followers(_start, 4);
    EXIT WHEN jsonb_array_length(_r->'result') = 0;
    _paged = _paged || jsonb_path_query_array(_r, '$.result[*].follower');
    _start = _r->'result'->-1->>'follower';
  END LOOP;
  IF _paged IS DISTINCT FROM _all THEN
    RAISE EXCEPTION 'pages of 4: expected %, got %', _all, _paged;
  END IF;

  PERFORM hivemind_app.insert_follows(ARRAY[ROW(
    (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'cfw-late'),
    (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'cfw-account'), 2)::hivemind_app.follow_ids]);
  _r = pg_temp.cfw_followers('cfw-b', 2);
  IF jsonb_path_query_array(_r, '$.result[*].follower') IS DISTINCT FROM '["cfw-late", "cfw-start"]'::JSONB THEN
    RAISE EXCEPTION 'after a new follow by cfw-late: expected ["cfw-late", "cfw-start"], got %', _r;
  END IF;

  _r = pg_temp.cfw_followers('', 1000, 'ignore');
  IF jsonb_path_query_array(_r, '$.result[*].follower') IS DISTINCT FROM '["cfw-muter"]'::JSONB THEN
    RAISE EXCEPTION 'ignore list: expected ["cfw-muter"], got %', _r;
  END IF;
END
$$;

ROLLBACK;
