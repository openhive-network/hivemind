-- The vote-free bridge calls (*_v2) and bridge.list_votes on a post with more than
-- 1000 votes, through hivemind_endpoints.home. Seeds its own accounts, post and votes
-- in a transaction it rolls back, so it runs on any installed hivemind schema,
-- including an empty chain:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/bridge_vote_free_calls.sql
--
-- 1101 voters: vt-0001 .. vt-1100, then vt-late, whose account id sorts after the
-- first 1000 voters, so the embedded active_votes list (cut at 1000 by voter id)
-- drops it. vt-0001 has the largest |rshares| (a downvote).

\set ON_ERROR_STOP 1
BEGIN;

INSERT INTO hivemind_app.hive_accounts (name, created_at)
SELECT 'vt-' || lpad(i::TEXT, 4, '0'), '2016-06-01' FROM generate_series(1, 1100) i ORDER BY i;
INSERT INTO hivemind_app.hive_accounts (name, created_at) VALUES ('vt-late', '2016-06-01');
INSERT INTO hivemind_app.hive_accounts (name, created_at) VALUES ('vt-author', '2016-06-01'), ('vt-novote', '2016-06-01');
INSERT INTO hivemind_app.hive_permlink_data (permlink) VALUES ('vt-post');
INSERT INTO hivemind_app.hive_category_data (category) VALUES ('vt-cat');

SELECT nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id')) AS post_id \gset

INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, block_num, block_num_created, total_votes)
SELECT :post_id, :post_id, 0,
  (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'vt-author'),
  (SELECT id FROM hivemind_app.hive_permlink_data WHERE permlink = 'vt-post'),
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'vt-cat'),
  '2016-06-01', 0, 1, 1, 1101;
INSERT INTO hivemind_app.hive_post_data (id, title, body, json) VALUES (:post_id, 'votes', 'a post with 1101 votes', '{}');

INSERT INTO hivemind_app.hive_votes (post_id, voter_id, author_id, permlink_id, weight, rshares, vote_percent, last_update, block_num)
SELECT hp.id, ha.id, hp.author_id, hp.permlink_id, 1,
  (CASE WHEN ha.name = 'vt-0001' THEN -5000000 WHEN ha.name = 'vt-late' THEN 777 ELSE substr(ha.name, 4)::INT * 1000 END),
  (CASE WHEN ha.name = 'vt-0001' THEN -10000 WHEN ha.name = 'vt-late' THEN 5000 ELSE 10000 END),
  '2016-06-02', 1
FROM hivemind_app.hive_accounts ha, hivemind_app.hive_posts hp
WHERE hp.id = :post_id AND (ha.name ~ '^vt-[0-9]{4}$' OR ha.name = 'vt-late');

DO $$
DECLARE
  _old JSONB;
  _new JSONB;
BEGIN
  IF (SELECT max(voter_id) FROM hivemind_app.hive_votes v JOIN hivemind_app.hive_accounts ha ON ha.id = v.voter_id WHERE ha.name ~ '^vt-[0-9]{4}$')
     > (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'vt-late') THEN
    RAISE EXCEPTION 'setup: vt-late must have the highest voter id';
  END IF;

  _old = hivemind_endpoints.home('{"jsonrpc": "2.0", "id": 1, "method": "bridge.get_post", "params": {"author": "vt-author", "permlink": "vt-post", "observer": "vt-late"}}')::JSONB;
  _new = hivemind_endpoints.home('{"jsonrpc": "2.0", "id": 1, "method": "bridge.get_post_v2", "params": {"author": "vt-author", "permlink": "vt-post", "observer": "vt-late"}}')::JSONB;
  IF NOT _old ? 'result' OR NOT _new ? 'result' THEN
    RAISE EXCEPTION 'get_post / get_post_v2 failed: % / %', _old, _new;
  END IF;
  _old = _old->'result';
  _new = _new->'result';

  -- today's behaviour: the embedded list stops at 1000 votes and lacks the observer's
  IF jsonb_array_length(_old->'active_votes') <> 1000 OR _old->'active_votes' @> '[{"voter": "vt-late"}]' THEN
    RAISE EXCEPTION 'get_post: expected 1000 active_votes without vt-late, got % entries', jsonb_array_length(_old->'active_votes');
  END IF;

  IF _new ? 'active_votes' THEN
    RAISE EXCEPTION 'get_post_v2: active_votes must be absent';
  END IF;
  IF _new ? 'top_votes' THEN
    RAISE EXCEPTION 'get_post_v2: top_votes must be absent when not asked for';
  END IF;
  IF _new->'observer_vote' IS DISTINCT FROM '{"rshares": 777, "percent": 5000}'::JSONB THEN
    RAISE EXCEPTION 'get_post_v2: observer_vote %, expected {"rshares": 777, "percent": 5000}', _new->'observer_vote';
  END IF;
  IF (_new->'stats'->>'total_votes')::INT <> 1101 THEN
    RAISE EXCEPTION 'get_post_v2: stats.total_votes %, expected 1101', _new->'stats'->'total_votes';
  END IF;
  IF (_old - 'active_votes') <> (_new - 'observer_vote') THEN
    RAISE EXCEPTION 'get_post_v2 differs from get_post outside votes: % vs %', _old - 'active_votes', _new - 'observer_vote';
  END IF;
  IF length(_new::TEXT) >= length(_old::TEXT) THEN
    RAISE EXCEPTION 'get_post_v2 (% bytes) is not smaller than get_post (% bytes)', length(_new::TEXT), length(_old::TEXT);
  END IF;
  RAISE NOTICE 'get_post: % bytes, get_post_v2: % bytes', length(_old::TEXT), length(_new::TEXT);
END
$$;

DO $$
DECLARE
  _r JSONB;
BEGIN
  _r = hivemind_endpoints.home('{"jsonrpc": "2.0", "id": 1, "method": "bridge.get_post_v2", "params": {"author": "vt-author", "permlink": "vt-post", "observer": "vt-novote"}}')::JSONB;
  IF NOT _r->'result' ? 'observer_vote' OR _r->'result'->'observer_vote' <> 'null'::JSONB THEN
    RAISE EXCEPTION 'get_post_v2, observer who did not vote: observer_vote must be null, got %', _r;
  END IF;

  _r = hivemind_endpoints.home('{"jsonrpc": "2.0", "id": 1, "method": "bridge.get_post_v2", "params": {"author": "vt-author", "permlink": "vt-post"}}')::JSONB;
  IF NOT _r->'result' ? 'observer_vote' OR _r->'result'->'observer_vote' <> 'null'::JSONB THEN
    RAISE EXCEPTION 'get_post_v2, no observer: observer_vote must be null, got %', _r->'result'->'observer_vote';
  END IF;

  _r = hivemind_endpoints.home('{"jsonrpc": "2.0", "id": 1, "method": "bridge.get_post_v2", "params": {"author": "vt-author", "permlink": "vt-post", "top_votes": 3}}')::JSONB;
  IF _r->'result'->'top_votes' IS DISTINCT FROM
     '[{"voter": "vt-0001", "rshares": -5000000, "percent": -10000}, {"voter": "vt-1100", "rshares": 1100000, "percent": 10000}, {"voter": "vt-1099", "rshares": 1099000, "percent": 10000}]'::JSONB THEN
    RAISE EXCEPTION 'get_post_v2 top_votes=3: got %', _r->'result'->'top_votes';
  END IF;

  _r = hivemind_endpoints.home('{"jsonrpc": "2.0", "id": 1, "method": "bridge.get_post_v2", "params": {"author": "vt-author", "permlink": "vt-post", "top_votes": 0}}')::JSONB;
  IF _r->'result' ? 'top_votes' THEN
    RAISE EXCEPTION 'get_post_v2 top_votes=0: top_votes must be absent';
  END IF;
END
$$;

-- the other *_v2 calls build the same post object as their old counterparts
DO $$
DECLARE
  _call RECORD;
  _old JSONB;
  _new JSONB;
BEGIN
  FOR _call IN
    SELECT * FROM (VALUES
      ('bridge.get_ranked_posts', '{"sort": "created", "limit": 1, "observer": "vt-late"}'::JSONB),
      ('bridge.get_account_posts', '{"sort": "posts", "account": "vt-author", "limit": 1, "observer": "vt-late"}'::JSONB),
      ('bridge.get_discussion', '{"author": "vt-author", "permlink": "vt-post", "observer": "vt-late"}'::JSONB)
    ) AS c(method, params)
  LOOP
    _old = hivemind_endpoints.home(json_build_object('jsonrpc', '2.0', 'id', 1, 'method', _call.method, 'params', _call.params))::JSONB;
    _new = hivemind_endpoints.home(json_build_object('jsonrpc', '2.0', 'id', 1, 'method', _call.method || '_v2', 'params', _call.params))::JSONB;
    IF NOT _old ? 'result' OR NOT _new ? 'result' THEN
      RAISE EXCEPTION '% / %_v2 failed: % / %', _call.method, _call.method, _old, _new;
    END IF;
    IF jsonb_typeof(_old->'result') = 'object' THEN
      _old = _old->'result'->'vt-author/vt-post';
      _new = _new->'result'->'vt-author/vt-post';
    ELSE
      _old = _old->'result'->0;
      _new = _new->'result'->0;
    END IF;
    IF _old->>'permlink' IS DISTINCT FROM 'vt-post' THEN
      RAISE EXCEPTION '%: expected the seeded post, got %', _call.method, _old;
    END IF;
    IF _new ? 'active_votes' OR _new->'observer_vote' IS DISTINCT FROM '{"rshares": 777, "percent": 5000}'::JSONB THEN
      RAISE EXCEPTION '%_v2: active_votes must be absent and observer_vote set, got %', _call.method, _new;
    END IF;
    IF (_old - 'active_votes') <> (_new - 'observer_vote') THEN
      RAISE EXCEPTION '%_v2 differs from % outside votes: % vs %', _call.method, _call.method, _new - 'observer_vote', _old - 'active_votes';
    END IF;
  END LOOP;
END
$$;

-- bridge.list_votes pages through every voter exactly once
DO $$
DECLARE
  _page JSONB;
  _start TEXT := NULL;
  _seen TEXT[] := '{}';
  _pages INT := 0;
BEGIN
  LOOP
    _page = hivemind_endpoints.home(json_build_object('jsonrpc', '2.0', 'id', 1, 'method', 'bridge.list_votes',
      'params', jsonb_strip_nulls(jsonb_build_object('author', 'vt-author', 'permlink', 'vt-post', 'limit', 400, 'start', _start))))::JSONB;
    IF NOT _page ? 'result' THEN
      RAISE EXCEPTION 'list_votes failed: %', _page;
    END IF;
    _page = _page->'result';
    _pages = _pages + 1;
    EXIT WHEN jsonb_array_length(_page) = 0;
    IF _pages > 4 THEN
      RAISE EXCEPTION 'list_votes: no empty page after % pages, last page starts with %', _pages, _page->0->>'voter';
    END IF;
    IF jsonb_array_length(_page) > 400 THEN
      RAISE EXCEPTION 'list_votes: page of % entries, limit was 400', jsonb_array_length(_page);
    END IF;
    IF _pages = 1 AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(_page->0) k) <> ARRAY['percent', 'reputation', 'rshares', 'time', 'voter', 'weight'] THEN
      RAISE EXCEPTION 'list_votes: unexpected vote shape %', _page->0;
    END IF;
    _seen = _seen || ARRAY(SELECT jsonb_array_elements(_page)->>'voter');
    _start = _page->(jsonb_array_length(_page) - 1)->>'voter';
  END LOOP;

  IF _pages <> 4 THEN
    RAISE EXCEPTION 'list_votes: expected 3 pages and an empty one, got % pages', _pages;
  END IF;
  IF cardinality(_seen) <> 1101 OR (SELECT count(DISTINCT v) FROM unnest(_seen) v) <> 1101 OR NOT 'vt-late' = ANY(_seen) THEN
    RAISE EXCEPTION 'list_votes: % voters returned, % distinct, expected 1101 including vt-late', cardinality(_seen), (SELECT count(DISTINCT v) FROM unnest(_seen) v);
  END IF;

  _page = hivemind_endpoints.home('{"jsonrpc": "2.0", "id": 1, "method": "bridge.list_votes", "params": {"author": "vt-author", "permlink": "vt-post", "limit": 1001}}')::JSONB;
  IF NOT _page ? 'error' THEN
    RAISE EXCEPTION 'list_votes limit=1001 must be refused, got %', _page;
  END IF;
  _page = hivemind_endpoints.home('{"jsonrpc": "2.0", "id": 1, "method": "bridge.list_votes", "params": {"author": "vt-author"}}')::JSONB;
  IF NOT _page ? 'error' THEN
    RAISE EXCEPTION 'list_votes without permlink must be refused, got %', _page;
  END IF;
  _page = hivemind_endpoints.home('{"jsonrpc": "2.0", "id": 1, "method": "bridge.list_votes", "params": {"permlink": "vt-post"}}')::JSONB;
  IF NOT _page ? 'error' THEN
    RAISE EXCEPTION 'list_votes without author must be refused, got %', _page;
  END IF;
END
$$;

ROLLBACK;
