-- database_api.find_comments for an author with a long post history. The function's
-- cached generic plan used to walk the author's every post (hive_posts_author_id_id_idx)
-- and probe each one's permlink, so one pair cost as much as the author's history. Seeds
-- its own accounts and posts in a transaction it rolls back, so it runs on any installed
-- hivemind schema, including an empty chain:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/database_api_find_comments_lookup.sql
--
-- fc-heavy has 5000 live posts fc-p-NNNN, a muted fc-muted and a deleted fc-deleted;
-- fc-other has fc-o-1, and 3000 more authors fc-a-NNNN one post each, so the planner's
-- average posts per author, as on mainnet, is far below fc-heavy's count.

\set ON_ERROR_STOP 1
BEGIN;

INSERT INTO hivemind_app.hive_accounts (id, name, created_at)
SELECT (SELECT max(id) FROM hivemind_app.hive_accounts) + a.n, a.name, '2016-06-01'
FROM unnest(ARRAY['fc-heavy', 'fc-other'] || ARRAY(SELECT 'fc-a-' || lpad(i::TEXT, 4, '0') FROM generate_series(1, 3000) i)) WITH ORDINALITY AS a(name, n);
INSERT INTO hivemind_app.hive_permlink_data (permlink)
SELECT 'fc-p-' || lpad(i::TEXT, 4, '0') FROM generate_series(1, 5000) i ORDER BY i;
INSERT INTO hivemind_app.hive_permlink_data (permlink)
SELECT 'fc-a-' || lpad(i::TEXT, 4, '0') FROM generate_series(1, 3000) i ORDER BY i;
INSERT INTO hivemind_app.hive_permlink_data (permlink) VALUES ('fc-muted'), ('fc-deleted'), ('fc-o-1');
INSERT INTO hivemind_app.hive_category_data (category) VALUES ('fc-cat');

INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, block_num, block_num_created, is_muted, counter_deleted)
SELECT p.id, p.id, 0, ha.id, hpd.id, (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'fc-cat'),
  '2016-06-01', 0, 1, 1, hpd.permlink = 'fc-muted', CASE WHEN hpd.permlink = 'fc-deleted' THEN 1 ELSE 0 END
FROM (
  SELECT permlink, nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id'))::INT AS id
  FROM hivemind_app.hive_permlink_data
  WHERE permlink ~ '^fc-[pa]-[0-9]{4}$' OR permlink IN ('fc-muted', 'fc-deleted', 'fc-o-1')
  ORDER BY permlink
) p
JOIN hivemind_app.hive_permlink_data hpd ON hpd.permlink = p.permlink
JOIN hivemind_app.hive_accounts ha ON ha.name = CASE WHEN p.permlink = 'fc-o-1' THEN 'fc-other'
                                                      WHEN p.permlink LIKE 'fc-a-%' THEN p.permlink
                                                      ELSE 'fc-heavy' END;

INSERT INTO hivemind_app.hive_post_data (id, title, body, json)
SELECT hp.id, '', 'post ' || hpd.permlink, '{}'
FROM hivemind_app.hive_posts hp
JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
JOIN hivemind_app.hive_accounts ha ON ha.id = hp.author_id
WHERE ha.name ~ '^fc-(heavy|other|a-[0-9]{4})$';

-- So the planner knows fc-heavy's history is long; the lock it holds until the rollback
-- also keeps autovacuum from recording these tables with ~0 live tuples meanwhile.
ANALYZE hivemind_app.hive_accounts, hivemind_app.hive_permlink_data, hivemind_app.hive_posts;

DO $$
DECLARE
  _request JSONB := '{"comments": [
    ["fc-heavy", "fc-p-2500"], ["fc-other", "fc-o-1"], ["fc-heavy", "fc-muted"], "fc-heavy/fc-p-0001",
    ["fc-heavy", "fc-deleted"], ["fc-heavy", "fc-p-2500"], ["fc-other", "fc-p-0001"], ["fc-nobody", "fc-p-0001"],
    ["", "fc-p-0001"], ["fc-heavy"], ["fc-heavy", "fc-p-0007"]]}';
  _expected TEXT[] := ARRAY['fc-heavy/fc-p-2500', 'fc-other/fc-o-1', 'fc-heavy/fc-p-2500', 'fc-heavy/fc-p-0007'];
  _r JSONB;
  _got TEXT[];
  _walked BIGINT;
  _probed BIGINT;
BEGIN
  IF to_regclass('hivemind_app.hive_posts_author_id_id_idx') IS NULL THEN
    RAISE EXCEPTION 'setup: hive_posts_author_id_id_idx is missing, so a walk of it cannot be ruled out';
  END IF;

  -- This transaction's own index counters, not yet flushed to pg_stat_user_indexes.
  _walked = pg_stat_get_xact_tuples_returned('hivemind_app.hive_posts_author_id_id_idx'::regclass);
  _probed = pg_stat_get_xact_numscans('hivemind_app.hive_posts_ux1'::regclass);

  -- Calls 6 on run the backend's cached generic plan; the last ones force it.
  FOR _i IN 1..9 LOOP
    IF _i = 8 THEN
      PERFORM set_config('plan_cache_mode', 'force_generic_plan', true);
    END IF;
    _r = hivemind_endpoints.database_api_find_comments(_request);
    _got = ARRAY(SELECT c->>'author' || '/' || (c->>'permlink') FROM jsonb_array_elements(_r->'comments') WITH ORDINALITY AS e(c, n) ORDER BY n);
    IF _got IS DISTINCT FROM _expected THEN
      RAISE EXCEPTION 'find_comments call %: %, expected %', _i, _got, _expected;
    END IF;
  END LOOP;

  IF (_r->'comments'->0->>'body') <> 'post fc-p-2500' THEN
    RAISE EXCEPTION 'find_comments: first post %, expected the body of fc-heavy/fc-p-2500', _r->'comments'->0;
  END IF;

  _walked = pg_stat_get_xact_tuples_returned('hivemind_app.hive_posts_author_id_id_idx'::regclass) - _walked;
  _probed = pg_stat_get_xact_numscans('hivemind_app.hive_posts_ux1'::regclass) - _probed;
  IF _walked <> 0 THEN
    RAISE EXCEPTION 'find_comments read % tuples of hive_posts_author_id_id_idx, expected none', _walked;
  END IF;
  IF _probed = 0 THEN
    RAISE EXCEPTION 'find_comments never probed hive_posts_ux1';
  END IF;

  _r = hivemind_endpoints.database_api_find_comments('{"comments": [["fc-heavy", "fc-muted"], ["fc-heavy", "fc-deleted"], ["fc-nobody", "x"]]}');
  IF _r <> '{"comments": []}' THEN
    RAISE EXCEPTION 'find_comments of no live post: %, expected an empty list', _r;
  END IF;
END
$$;

ROLLBACK;
