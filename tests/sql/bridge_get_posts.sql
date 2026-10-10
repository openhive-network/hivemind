-- bridge.get_posts through hivemind_endpoints.home: each entry equals bridge.get_post_v2
-- for the same post, observer and top_votes, in request order, with null for a missing
-- or deleted post. Seeds its own accounts, posts and vote in a transaction it rolls
-- back, so it runs on any installed hivemind schema, including an empty chain:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/bridge_get_posts.sql

\set ON_ERROR_STOP 1
BEGIN;

INSERT INTO hivemind_app.hive_accounts (name, created_at) VALUES ('gp-author', '2016-06-01'), ('gp-voter', '2016-06-01');
INSERT INTO hivemind_app.hive_permlink_data (permlink) VALUES ('gp-one'), ('gp-two'), ('gp-gone');
INSERT INTO hivemind_app.hive_category_data (category) VALUES ('gp-cat');

INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, block_num, block_num_created, total_votes, counter_deleted)
SELECT p.id, p.id, 0,
  (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'gp-author'),
  p.permlink_id,
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'gp-cat'),
  '2016-06-01', 0, 1, 1, (CASE WHEN p.permlink = 'gp-two' THEN 1 ELSE 0 END), (CASE WHEN p.permlink = 'gp-gone' THEN 1 ELSE 0 END)
FROM (
  SELECT nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id')) AS id, hpd.id AS permlink_id, hpd.permlink
  FROM hivemind_app.hive_permlink_data hpd
  WHERE hpd.permlink IN ('gp-one', 'gp-two', 'gp-gone')
) p;
INSERT INTO hivemind_app.hive_post_data (id, title, body, json)
SELECT hp.id, hpd.permlink, 'body of ' || hpd.permlink, '{}'
FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
WHERE hpd.permlink IN ('gp-one', 'gp-two', 'gp-gone');

INSERT INTO hivemind_app.hive_votes (post_id, voter_id, author_id, permlink_id, weight, rshares, vote_percent, last_update, block_num)
SELECT hp.id, (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'gp-voter'), hp.author_id, hp.permlink_id, 1, 4242, 2500, '2016-06-02', 1
FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
WHERE hpd.permlink = 'gp-two';

DO $$
DECLARE
  _r JSONB;
  _one JSONB;
  _two JSONB;
  _expected JSONB;
  _bad RECORD;
BEGIN
  _one = hivemind_endpoints.home('{"jsonrpc": "2.0", "id": 1, "method": "bridge.get_post_v2", "params": {"author": "gp-author", "permlink": "gp-one", "observer": "gp-voter", "top_votes": 2}}')::JSONB->'result';
  _two = hivemind_endpoints.home('{"jsonrpc": "2.0", "id": 1, "method": "bridge.get_post_v2", "params": {"author": "gp-author", "permlink": "gp-two", "observer": "gp-voter", "top_votes": 2}}')::JSONB->'result';
  IF _one IS NULL OR _two IS NULL OR _two->'observer_vote' IS DISTINCT FROM '{"rshares": 4242, "percent": 2500}'::JSONB THEN
    RAISE EXCEPTION 'setup: get_post_v2 returned % / %', _one, _two;
  END IF;

  _expected = jsonb_build_array(_two, NULL, NULL, _one, _two);
  _r = hivemind_endpoints.home('{"jsonrpc": "2.0", "id": 1, "method": "bridge.get_posts", "params": {"posts": [["gp-author", "gp-two"], ["gp-author", "gp-missing"], ["gp-author", "gp-gone"], ["gp-author", "gp-one"], ["gp-author", "gp-two"]], "observer": "gp-voter", "top_votes": 2}}')::JSONB;
  IF _r->'result' IS DISTINCT FROM _expected THEN
    RAISE EXCEPTION 'get_posts: got %, expected %', _r, _expected;
  END IF;

  _r = hivemind_endpoints.home('{"jsonrpc": "2.0", "id": 1, "method": "bridge.get_posts", "params": [[["gp-author", "gp-one"]]]}')::JSONB;
  _one = hivemind_endpoints.home('{"jsonrpc": "2.0", "id": 1, "method": "bridge.get_post_v2", "params": {"author": "gp-author", "permlink": "gp-one"}}')::JSONB->'result';
  IF _r->'result' IS DISTINCT FROM jsonb_build_array(_one) OR _one ? 'top_votes' THEN
    RAISE EXCEPTION 'get_posts (positional, no observer): got %, expected [%]', _r, _one;
  END IF;

  FOR _bad IN SELECT * FROM (VALUES
    ('{"posts": []}'),
    ('{"posts": [["gp-author", "gp-one"], ["gp-author"]]}'),
    ('{"posts": [["gp-author", 1]]}'),
    ('{"posts": ["gp-author", "gp-one"]}'),
    ('{"posts": [["GP", "gp-one"]]}'),
    ('{"posts": [["gp-author", ""]]}'),
    ('{"posts": [["gp-author", "gp-one"]], "top_votes": 11}'),
    ('{"posts": [["gp-author", "gp-one"]], "observer": "gp-nobody"}'),
    ('{"posts": "gp-author/gp-one"}'),
    ('{"observer": "gp-voter"}')
  ) AS t(params) LOOP
    _r = hivemind_endpoints.home(json_build_object('jsonrpc', '2.0', 'id', 1, 'method', 'bridge.get_posts', 'params', _bad.params::JSON))::JSONB;
    IF (_r->'error'->>'code') IS DISTINCT FROM '-32602' THEN
      RAISE EXCEPTION 'get_posts %: expected error -32602, got %', _bad.params, _r;
    END IF;
  END LOOP;

  _r = hivemind_endpoints.home(json_build_object('jsonrpc', '2.0', 'id', 1, 'method', 'bridge.get_posts',
    'params', json_build_object('posts', (SELECT json_agg(json_build_array('gp-author', 'gp-one')) FROM generate_series(1, 101)))))::JSONB;
  IF (_r->'error'->>'code') IS DISTINCT FROM '-32602' THEN
    RAISE EXCEPTION 'get_posts with 101 entries: expected error -32602, got %', left(_r::TEXT, 300);
  END IF;
  _r = hivemind_endpoints.home(json_build_object('jsonrpc', '2.0', 'id', 1, 'method', 'bridge.get_posts',
    'params', json_build_object('posts', (SELECT json_agg(json_build_array('gp-author', 'gp-one')) FROM generate_series(1, 100)))))::JSONB;
  IF jsonb_array_length(_r->'result') IS DISTINCT FROM 100 THEN
    RAISE EXCEPTION 'get_posts with 100 entries: expected 100 results, got %', left(_r::TEXT, 300);
  END IF;
END
$$;

ROLLBACK;
