-- hive_accounts.id is HAF's account id: the seeded genesis accounts miners, null, temp and
-- initminer have their HAF ids 0-3, and "no account" is the '' sentinel's -1, so miners
-- (id 0) is a real account. Checks the seed rows, the account lookups and, on a post
-- miners votes on with a voter miners mutes, that bridge.list_votes lists miners' vote on
-- its first page and drops the muted voter's for observer miners only. Seeds its own
-- accounts, post and votes in a transaction it rolls back, so it runs on any installed
-- hivemind schema, including an empty chain:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/account_sentinel_ids.sql

\set ON_ERROR_STOP 1
BEGIN;

DO $$
DECLARE
  _seeds TEXT;
BEGIN
  SELECT string_agg(format('%s:%s', id, name), ' ' ORDER BY id) INTO _seeds FROM hivemind_app.hive_accounts WHERE id < 4;
  IF _seeds IS DISTINCT FROM '-1: 0:miners 1:null 2:temp 3:initminer' THEN
    RAISE EXCEPTION 'seed accounts: expected -1: 0:miners 1:null 2:temp 3:initminer, got %', _seeds;
  END IF;
  IF (SELECT author_id FROM hivemind_app.hive_posts WHERE id = 0) IS DISTINCT FROM -1 THEN
    RAISE EXCEPTION 'sentinel post 0: expected author -1, got %', (SELECT author_id FROM hivemind_app.hive_posts WHERE id = 0);
  END IF;
  IF EXISTS (SELECT NULL FROM information_schema.columns
             WHERE table_schema = 'hivemind_app' AND table_name = 'hive_accounts'
               AND (column_name = 'haf_id' OR (column_name = 'id' AND column_default IS NOT NULL))) THEN
    RAISE EXCEPTION 'hive_accounts still numbers accounts itself (a haf_id column or a default id)';
  END IF;
  IF EXISTS (SELECT NULL FROM hivemind_app.hive_communities WHERE id IN (-1, 0)) THEN
    RAISE EXCEPTION 'a community has the id of the sentinel or of miners, so 0 no longer means "no community"';
  END IF;

  IF hivemind_postgrest_utilities.find_account_id('miners', True) <> 0 OR hivemind_app.find_account_id('miners', True) <> 0 THEN
    RAISE EXCEPTION 'miners: expected id 0';
  END IF;
  IF hivemind_postgrest_utilities.find_account_id('', False) <> -1 OR hivemind_app.find_account_id('', False) <> -1 THEN
    RAISE EXCEPTION 'an empty name: expected -1';
  END IF;
  IF hivemind_postgrest_utilities.find_account_id('as-nobody', False) <> -1 OR hivemind_app.find_account_id('as-nobody', False) <> -1 THEN
    RAISE EXCEPTION 'a missing account: expected -1';
  END IF;
  BEGIN
    PERFORM hivemind_postgrest_utilities.find_account_id('as-nobody', True);
    RAISE EXCEPTION 'a missing account checked: expected an error';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE '%Account as-nobody does not exist%' THEN
      RAISE;
    END IF;
  END;
END
$$;

INSERT INTO hivemind_app.hive_accounts (id, name, created_at)
SELECT (SELECT max(id) FROM hivemind_app.hive_accounts) + a.n, a.name, '2016-06-01'
FROM unnest(ARRAY['as-author', 'as-voter']) WITH ORDINALITY AS a(name, n);
INSERT INTO hivemind_app.hive_permlink_data (permlink) VALUES ('as-post');
INSERT INTO hivemind_app.hive_category_data (category) VALUES ('as-cat');

SELECT nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id')) AS post_id \gset

INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, block_num, block_num_created, total_votes)
SELECT :post_id, :post_id, 0,
  (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'as-author'),
  (SELECT id FROM hivemind_app.hive_permlink_data WHERE permlink = 'as-post'),
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'as-cat'),
  '2016-06-01', 0, 1, 1, 2;
INSERT INTO hivemind_app.hive_votes (post_id, voter_id, author_id, permlink_id, weight, rshares, vote_percent, last_update, block_num)
SELECT hp.id, ha.id, hp.author_id, hp.permlink_id, 1, 1000, 10000, '2016-06-02', 1
FROM hivemind_app.hive_accounts ha, hivemind_app.hive_posts hp
WHERE hp.id = :post_id AND ha.name IN ('miners', 'as-voter');
INSERT INTO hivemind_app.muted (follower, following, block_num)
SELECT 0, (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'as-voter'), 1;

CREATE FUNCTION pg_temp.as_voters(_params JSONB) RETURNS JSONB LANGUAGE sql AS $$
  SELECT jsonb_path_query_array(hivemind_endpoints.home(json_build_object('jsonrpc', '2.0', 'id', 1, 'method', 'bridge.list_votes',
    'params', jsonb_build_object('author', 'as-author', 'permlink', 'as-post') || _params))::JSONB, '$.result[*].voter')
$$;

DO $$
DECLARE
  _r JSONB;
BEGIN
  _r = pg_temp.as_voters('{}');
  IF _r IS DISTINCT FROM '["miners", "as-voter"]'::JSONB THEN
    RAISE EXCEPTION 'bridge.list_votes, no start: expected ["miners", "as-voter"], got %', _r;
  END IF;
  _r = pg_temp.as_voters('{"start": "miners"}');
  IF _r IS DISTINCT FROM '["as-voter"]'::JSONB THEN
    RAISE EXCEPTION 'bridge.list_votes after miners: expected ["as-voter"], got %', _r;
  END IF;
  _r = pg_temp.as_voters('{"observer": "miners"}');
  IF _r IS DISTINCT FROM '["miners"]'::JSONB THEN
    RAISE EXCEPTION 'bridge.list_votes, observer miners, who muted as-voter: expected ["miners"], got %', _r;
  END IF;
  _r = pg_temp.as_voters('{"observer": ""}');
  IF _r IS DISTINCT FROM '["miners", "as-voter"]'::JSONB THEN
    RAISE EXCEPTION 'bridge.list_votes, empty observer: expected ["miners", "as-voter"], got %', _r;
  END IF;
END
$$;

ROLLBACK;
\echo account sentinel ids: -1 is no account, miners is account 0
