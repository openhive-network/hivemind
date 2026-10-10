-- bridge.get_discussion on a thread larger than its cap, through hivemind_endpoints.home.
-- Seeds its own accounts and posts in a transaction it rolls back, so it runs on any
-- installed hivemind schema, including an empty chain:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/bridge_get_discussion_cap.sql
--
-- The thread is dc-author/dc-root, cap - 1 direct replies dc-r-NNNN, and one reply
-- dc-deep to dc-r-0001 created last. That is cap + 1 posts; the one with the highest
-- id, dc-deep, is cut, so dc-r-0001 must stop listing it.

\set ON_ERROR_STOP 1
BEGIN;

SELECT hivemind_postgrest_utilities.get_max_discussion_posts_limit() AS cap \gset

INSERT INTO hivemind_app.hive_accounts (name, created_at) VALUES ('dc-author', '2016-06-01'), ('dc-replier', '2016-06-01');
INSERT INTO hivemind_app.hive_permlink_data (permlink) VALUES ('dc-root'), ('dc-deep');
INSERT INTO hivemind_app.hive_permlink_data (permlink)
SELECT 'dc-r-' || lpad(i::TEXT, 4, '0') FROM generate_series(1, :cap - 1) i ORDER BY i;
INSERT INTO hivemind_app.hive_category_data (category) VALUES ('dc-cat');

SELECT nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id')) AS root_id \gset

INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, block_num, block_num_created, children)
SELECT :root_id, :root_id, 0,
  (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'dc-author'),
  (SELECT id FROM hivemind_app.hive_permlink_data WHERE permlink = 'dc-root'),
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'dc-cat'),
  '2016-06-01', 0, 1, 1, :cap;

INSERT INTO hivemind_app.hive_posts (root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, block_num, block_num_created)
SELECT :root_id, :root_id,
  (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'dc-replier'),
  hpd.id,
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'dc-cat'),
  '2016-06-02', 1, 2, 2
FROM hivemind_app.hive_permlink_data hpd
WHERE hpd.permlink ~ '^dc-r-[0-9]{4}$'
ORDER BY hpd.permlink;

INSERT INTO hivemind_app.hive_posts (root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, block_num, block_num_created)
SELECT :root_id, hp.id,
  (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'dc-author'),
  (SELECT id FROM hivemind_app.hive_permlink_data WHERE permlink = 'dc-deep'),
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'dc-cat'),
  '2016-06-03', 2, 3, 3
FROM hivemind_app.hive_posts hp
JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
WHERE hpd.permlink = 'dc-r-0001';

INSERT INTO hivemind_app.hive_post_data (id, title, body, json)
SELECT hp.id, '', 'post ' || hp.id, '{}' FROM hivemind_app.hive_posts hp WHERE hp.root_id = :root_id;

DO $$
DECLARE
  _cap INT := hivemind_postgrest_utilities.get_max_discussion_posts_limit();
  _method TEXT;
  _r JSONB;
  _missing TEXT[];
BEGIN
  IF _cap <> 4000 THEN
    RAISE EXCEPTION 'get_max_discussion_posts_limit: %, expected 4000', _cap;
  END IF;
  IF (SELECT count(*) FROM hivemind_app.hive_posts WHERE root_id = (SELECT root_id FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id WHERE hpd.permlink = 'dc-root')) <> _cap + 1 THEN
    RAISE EXCEPTION 'setup: expected a thread of % posts', _cap + 1;
  END IF;

  FOREACH _method IN ARRAY ARRAY['bridge.get_discussion', 'bridge.get_discussion_v2'] LOOP
    _r = hivemind_endpoints.home(json_build_object('jsonrpc', '2.0', 'id', 1, 'method', _method, 'params', json_build_object('author', 'dc-author', 'permlink', 'dc-root')))::JSONB;
    IF NOT _r ? 'result' THEN
      RAISE EXCEPTION '% failed: %', _method, _r;
    END IF;
    _r = _r->'result';

    IF (SELECT count(*) FROM jsonb_object_keys(_r)) <> _cap THEN
      RAISE EXCEPTION '%: % posts returned, expected the cap %', _method, (SELECT count(*) FROM jsonb_object_keys(_r)), _cap;
    END IF;
    IF NOT _r ? 'dc-author/dc-root' OR _r ? 'dc-author/dc-deep' THEN
      RAISE EXCEPTION '%: expected the root and not the newest post dc-deep', _method;
    END IF;

    _missing = ARRAY(
      SELECT reply FROM jsonb_each(_r) post, jsonb_array_elements_text(post.value->'replies') reply
      WHERE NOT _r ? reply);
    IF cardinality(_missing) <> 0 THEN
      RAISE EXCEPTION '%: replies not in the result: %', _method, _missing;
    END IF;

    IF _r->'dc-replier/dc-r-0001'->'replies' <> '[]'::JSONB THEN
      RAISE EXCEPTION '%: dc-r-0001 replies %, expected []', _method, _r->'dc-replier/dc-r-0001'->'replies';
    END IF;
    IF jsonb_array_length(_r->'dc-author/dc-root'->'replies') <> _cap - 1
       OR _r->'dc-author/dc-root'->'replies'->0 <> '"dc-replier/dc-r-0001"'::JSONB THEN
      RAISE EXCEPTION '%: root lists % replies, expected % starting with dc-r-0001', _method, jsonb_array_length(_r->'dc-author/dc-root'->'replies'), _cap - 1;
    END IF;
  END LOOP;
END
$$;

-- under the cap nothing is cut: dc-r-0001 lists dc-deep again
DELETE FROM hivemind_app.hive_post_data WHERE id = (SELECT max(id) FROM hivemind_app.hive_posts WHERE parent_id = :root_id);
DELETE FROM hivemind_app.hive_posts WHERE id = (SELECT max(id) FROM hivemind_app.hive_posts WHERE parent_id = :root_id);

DO $$
DECLARE
  _cap INT := hivemind_postgrest_utilities.get_max_discussion_posts_limit();
  _r JSONB;
BEGIN
  _r = hivemind_endpoints.home('{"jsonrpc": "2.0", "id": 1, "method": "bridge.get_discussion", "params": {"author": "dc-author", "permlink": "dc-root"}}')::JSONB->'result';
  IF (SELECT count(*) FROM jsonb_object_keys(_r)) <> _cap OR NOT _r ? 'dc-author/dc-deep' THEN
    RAISE EXCEPTION 'thread of exactly the cap: % posts returned, expected % including dc-deep', (SELECT count(*) FROM jsonb_object_keys(_r)), _cap;
  END IF;
  IF _r->'dc-replier/dc-r-0001'->'replies' <> '["dc-author/dc-deep"]'::JSONB THEN
    RAISE EXCEPTION 'thread of exactly the cap: dc-r-0001 replies %, expected ["dc-author/dc-deep"]', _r->'dc-replier/dc-r-0001'->'replies';
  END IF;
END
$$;

ROLLBACK;
