-- truncate_body on the bridge post-list calls, through hivemind_endpoints.home. Seeds
-- its own account and post in a transaction it rolls back, so it runs on any installed
-- hivemind schema, including an empty chain:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/bridge_truncate_body.sql
--
-- The body is multi-byte, so a byte-based cut would show up as a different string.

\set ON_ERROR_STOP 1
BEGIN;

INSERT INTO hivemind_app.hive_accounts (name, created_at) VALUES ('tb-author', '2016-06-01');
INSERT INTO hivemind_app.hive_permlink_data (permlink) VALUES ('tb-post');
INSERT INTO hivemind_app.hive_category_data (category) VALUES ('tb-cat');
INSERT INTO hivemind_app.hive_tag_data (tag) VALUES ('tb-cat');

SELECT nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id')) AS post_id \gset

INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, block_num, block_num_created)
SELECT :post_id, :post_id, 0,
  (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'tb-author'),
  (SELECT id FROM hivemind_app.hive_permlink_data WHERE permlink = 'tb-post'),
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'tb-cat'),
  '2016-06-01', 0, 1, 1;
INSERT INTO hivemind_app.hive_post_data (id, title, body, json) VALUES (:post_id, 'truncate', 'Zażółć gęślą jaźń, a body longer than the cut', '{}');
INSERT INTO hivemind_app.hive_post_tags (post_id, tag_id) SELECT :post_id, id FROM hivemind_app.hive_tag_data WHERE tag = 'tb-cat';

DO $$
DECLARE
  _call RECORD;
  _full JSONB;
  _cut JSONB;
  _zero JSONB;
  _err JSONB;
BEGIN
  FOR _call IN
    SELECT * FROM (VALUES
      ('bridge.get_ranked_posts', '{"sort": "created", "limit": 1}'::JSONB),
      ('bridge.get_ranked_posts', '{"sort": "created", "tag": "tb-cat", "limit": 1}'::JSONB),
      ('bridge.get_ranked_posts_v2', '{"sort": "created", "limit": 1}'::JSONB),
      ('bridge.get_account_posts', '{"sort": "posts", "account": "tb-author", "limit": 1}'::JSONB),
      ('bridge.get_account_posts_v2', '{"sort": "posts", "account": "tb-author", "limit": 1}'::JSONB),
      ('bridge.get_account_posts_by_tag', '{"account": "tb-author", "tag": "tb-cat", "limit": 1}'::JSONB)
    ) AS c(method, params)
  LOOP
    _full = hivemind_endpoints.home(json_build_object('jsonrpc', '2.0', 'id', 1, 'method', _call.method, 'params', _call.params))::JSONB;
    _cut = hivemind_endpoints.home(json_build_object('jsonrpc', '2.0', 'id', 1, 'method', _call.method, 'params', _call.params || '{"truncate_body": 7}'))::JSONB;
    _zero = hivemind_endpoints.home(json_build_object('jsonrpc', '2.0', 'id', 1, 'method', _call.method, 'params', _call.params || '{"truncate_body": 0}'))::JSONB;
    IF NOT _full ? 'result' OR NOT _cut ? 'result' OR NOT _zero ? 'result' THEN
      RAISE EXCEPTION '% %: failed: % / % / %', _call.method, _call.params, _full, _cut, _zero;
    END IF;
    _full = _full->'result'->0;
    _cut = _cut->'result'->0;
    _zero = _zero->'result'->0;
    IF _full->>'permlink' IS DISTINCT FROM 'tb-post' THEN
      RAISE EXCEPTION '% %: expected the seeded post, got %', _call.method, _call.params, _full;
    END IF;
    IF _cut->>'body' IS DISTINCT FROM 'Zażółć ' THEN
      RAISE EXCEPTION '% % truncate_body=7: body %, expected "Zażółć "', _call.method, _call.params, _cut->'body';
    END IF;
    IF (_full - 'body') <> (_cut - 'body') THEN
      RAISE EXCEPTION '% % truncate_body=7 differs outside body: % vs %', _call.method, _call.params, _cut - 'body', _full - 'body';
    END IF;
    IF _zero <> _full THEN
      RAISE EXCEPTION '% % truncate_body=0 differs from no truncate_body: % vs %', _call.method, _call.params, _zero, _full;
    END IF;

    _err = hivemind_endpoints.home(json_build_object('jsonrpc', '2.0', 'id', 1, 'method', _call.method, 'params', _call.params || '{"truncate_body": -1}'))::JSONB;
    IF _err->'error'->>'message' IS DISTINCT FROM 'Assert Exception:truncate_body = -1 outside valid range [0:]' THEN
      RAISE EXCEPTION '% % truncate_body=-1: expected a range error, got %', _call.method, _call.params, _err;
    END IF;
  END LOOP;
END
$$;

ROLLBACK;
