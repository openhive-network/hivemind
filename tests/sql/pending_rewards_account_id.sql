-- get_account_pending_author_rewards and get_account_pending_curation_rewards find the account's
-- posts and votes by hivemind's hive_accounts.id, which hive_posts.author_id and
-- hive_votes.voter_id hold. Resolving the name to the HAF account id instead matched no row on
-- mainnet, where the two ids differ, so both endpoints answered all zeros for every account.
-- The accounts seeded here exist only in hive_accounts, so a HAF-id lookup cannot find them.
-- Seeds its own accounts, post and vote in a transaction it rolls back, so it runs on any
-- installed hivemind schema, including an empty chain:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/pending_rewards_account_id.sql
--
-- An empty chain has no head block, and the curation endpoint only counts votes of the last
-- eight days before it, so head_block_time is pinned for the transaction.

\set ON_ERROR_STOP 1
BEGIN;

CREATE OR REPLACE FUNCTION hivemind_app.head_block_time() RETURNS TIMESTAMP LANGUAGE sql STABLE
AS $$ SELECT TIMESTAMP '2026-11-18 12:00:00' $$;

INSERT INTO hivemind_app.hive_accounts (name, created_at) VALUES ('pr-author', '2016-06-01'), ('pr-voter', '2016-06-01');
INSERT INTO hivemind_app.hive_permlink_data (permlink) VALUES ('pr-post');
INSERT INTO hivemind_app.hive_category_data (category) VALUES ('pr-cat');

SELECT nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id')) AS post_id \gset

-- 10.000 HBD pending, column defaults otherwise (no beneficiaries); one vote holding all of the vote weight
INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth,
                                     block_num, block_num_created, pending_payout, total_vote_weight)
SELECT :post_id, :post_id, 0,
  (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'pr-author'),
  (SELECT id FROM hivemind_app.hive_permlink_data WHERE permlink = 'pr-post'),
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'pr-cat'),
  '2026-11-17', 0, 1, 1, 10, 100;
INSERT INTO hivemind_app.hive_post_data (id, title, body, json) VALUES (:post_id, 'pending', 'a pending post', '{}');
INSERT INTO hivemind_app.hive_votes (post_id, voter_id, author_id, permlink_id, weight, rshares, vote_percent, last_update, block_num)
SELECT hp.id, (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'pr-voter'), hp.author_id, hp.permlink_id,
  100, 1000, 10000, '2026-11-17 12:00:00', 1
FROM hivemind_app.hive_posts hp WHERE hp.id = :post_id;

DO $$
DECLARE
  _author JSONB := to_jsonb(hivemind_endpoints.get_account_pending_author_rewards('pr-author'));
  _curation JSONB := to_jsonb(hivemind_endpoints.get_account_pending_curation_rewards('pr-voter'));
BEGIN
  -- IS DISTINCT FROM: a NULL must fail the check, not skip it
  IF (_author->>'pending_post_count')::INT IS DISTINCT FROM 1
     OR _author->'gross_reward_basis'->>'amount' IS DISTINCT FROM '10000' THEN
    RAISE EXCEPTION 'pending author rewards: expected 1 post and 10.000 HBD gross, got %', _author;
  END IF;
  -- curators get 50% of the 10.000 HBD, all of it to the one vote
  IF (_curation->>'pending_vote_count')::INT IS DISTINCT FROM 1
     OR _curation->'curation_reward_basis'->'total'->>'amount' IS DISTINCT FROM '5000' THEN
    RAISE EXCEPTION 'pending curation rewards: expected 1 vote and 5.000 HBD, got %', _curation;
  END IF;
END
$$;

ROLLBACK;
\echo pending_rewards_account_id: ok
