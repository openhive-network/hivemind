-- search-api.find_text and /search/posts under generic plans. A backend's cached plan for
-- a static plpgsql statement switches to a generic plan after five calls when that looks
-- cheaper, and pg_search 0.25.3 returns no rows from a generic plan that parses a plpgsql
-- variable, so every later search of that backend answered []. force_generic_plan makes
-- every cached plan generic from the first call. Seeds its own accounts and posts in a
-- transaction it rolls back, so it runs on any installed hivemind schema with pg_search,
-- including an empty chain, and skips without pg_search:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/find_text_generic_plan.sql

\set ON_ERROR_STOP 1
SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_search')
   AND to_regclass('hivemind_app.hive_post_data_bm25_idx') IS NOT NULL AS has_bm25 \gset
\if :has_bm25
BEGIN;

INSERT INTO hivemind_app.hive_accounts (name, created_at) VALUES ('gp-author', '2016-06-01'), ('gp-other', '2016-06-01');
INSERT INTO hivemind_app.hive_permlink_data (permlink) VALUES ('gp-post-1'), ('gp-post-2'), ('gp-post-3');
INSERT INTO hivemind_app.hive_category_data (category) VALUES ('gp-cat');

INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, block_num, block_num_created)
SELECT m.id + v.n, m.id + v.n, 0, ha.id, pd.id, (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'gp-cat'),
  '2016-06-01', 0, 1, 1
FROM (VALUES (1, 'gp-author'), (2, 'gp-author'), (3, 'gp-other')) v(n, author)
CROSS JOIN (SELECT coalesce(max(id), 0) AS id FROM hivemind_app.hive_posts) m
JOIN hivemind_app.hive_accounts ha ON ha.name = v.author
JOIN hivemind_app.hive_permlink_data pd ON pd.permlink = 'gp-post-' || v.n;

INSERT INTO hivemind_app.hive_post_data (id, title, body, json)
SELECT hp.id, 'gpzqxv', 'gpzqxv post ' || pd.permlink, '{}'
FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data pd ON pd.id = hp.permlink_id
WHERE pd.permlink LIKE 'gp-post-%';

SET LOCAL plan_cache_mode = force_generic_plan;

DO $$
DECLARE
  _call RECORD;
  _got INT;
BEGIN
  FOR _call IN
    SELECT * FROM (VALUES
      ('relevance', NULL, NULL, 3),
      ('created', NULL, NULL, 3),
      ('relevance', 'gp-author', NULL, 2),
      ('created', 'gp-author', NULL, 2),
      ('created', NULL, 'gp-post-3', 2),
      ('created', 'gp-author', 'gp-post-2', 1)
    ) c(sort, author, start_permlink, expected)
  LOOP
    -- A second call reuses the function's cached plans.
    FOR _i IN 1..2 LOOP
      _got = jsonb_array_length(hivemind_endpoints.search_api_find_text(jsonb_strip_nulls(jsonb_build_object(
        'pattern', 'gpzqxv', 'sort', _call.sort, 'author', _call.author,
        'start_author', CASE WHEN _call.start_permlink = 'gp-post-3' THEN 'gp-other'
                             WHEN _call.start_permlink IS NOT NULL THEN 'gp-author' END,
        'start_permlink', _call.start_permlink))));
      IF _got <> _call.expected THEN
        RAISE EXCEPTION 'find_text sort=% author=% start=% call %: % posts, expected %',
          _call.sort, _call.author, _call.start_permlink, _i, _got, _call.expected;
      END IF;
    END LOOP;
  END LOOP;

  _got = (SELECT count(*) FROM hivemind_endpoints.search_posts(q => 'gpzqxv', sort => 'relevance', "page-size" => 20));
  IF _got <> 3 THEN
    RAISE EXCEPTION '/search/posts: % posts, expected 3', _got;
  END IF;
END
$$;

ROLLBACK;
\else
\echo 'find_text_generic_plan: skipped, no pg_search BM25 index'
\endif
