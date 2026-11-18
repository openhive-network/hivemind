-- On the installed hivemind, checks inside one transaction that is rolled back that an
-- account hivemind registers takes HAF's account id, whatever order HAF numbered the
-- accounts in, and that the pending-rewards endpoints, which look an account up in HAF,
-- read that account's own posts and votes:
--   - ak-first, ak-second and ak-third are created in that operation order, but HAF
--     numbers them in the opposite order;
--   - ak-second authors a pending post and ak-third votes on it.
-- Seeds blocks and HAF accounts after HAF's last block and account (an empty HAF, as
-- .aidev/test-stack.compose.yml starts it, has none).
--   psql -X -v ON_ERROR_STOP=1 -f .aidev/account_keyspace_check.sql
\set QUIET on
BEGIN;
SET LOCAL statement_timeout = '300s';

SELECT hive.disable_fk_of_irreversible();

CREATE TEMP TABLE ak_base AS
SELECT COALESCE(max(num), 0) AS b0,
       GREATEST((SELECT max(id) FROM hafd.accounts), (SELECT max(id) FROM hivemind_app.hive_accounts)) + 1 AS a0
FROM hafd.blocks;
GRANT SELECT ON ak_base TO hivemind;

INSERT INTO hafd.blocks
SELECT ak.b0 + b, ( '\xA1DD' || lpad( b::TEXT, 2, '0' ) )::bytea, '\xCAFE20',
       date_trunc( 'second', now() AT TIME ZONE 'UTC' ) - INTERVAL '1 hour' + b * INTERVAL '3 seconds',
       5, '\x4007', E'[]', '\x2157', 'STM65w', 1000, 1000, 1000000, 1000, 1000, 1000, 2000, 2000
FROM generate_series( 0, 3 ) AS b, ak_base ak
WHERE ak.b0 + b > 0
ON CONFLICT DO NOTHING;

-- (name, block and HAF id offset): created in block order, numbered the other way round
CREATE TEMP TABLE ak_accounts ( name TEXT, block INT, haf_offset INT );
INSERT INTO ak_accounts VALUES ( 'ak-first', 1, 2 ), ( 'ak-second', 2, 1 ), ( 'ak-third', 3, 0 );
GRANT SELECT ON ak_accounts TO hivemind;

INSERT INTO hafd.accounts ( id, name, block_num )
SELECT ak.a0 + a.haf_offset, a.name, ak.b0 + a.block FROM ak_accounts a, ak_base ak;

UPDATE hafd.contexts SET current_block_num = ( SELECT b0 + 3 FROM ak_base ), irreversible_block = ( SELECT b0 + 3 FROM ak_base )
WHERE name = 'hivemind_app';

SET LOCAL ROLE hivemind;

DELETE FROM hivemind_app._ops_staging;
INSERT INTO hivemind_app._ops_staging ( id, block_num, block_date, op_type_id, val )
SELECT a.block, ak.b0 + a.block, hivemind_app.head_block_time(), 9,  -- account_create_operation
       jsonb_build_object( 'new_account_name', a.name, 'json_metadata', '', 'posting_json_metadata', '' )
FROM ak_accounts a, ak_base ak;

DO $$
DECLARE
  _mismatched TEXT;
BEGIN
  IF ( SELECT count(*) FROM hivemind_app.accounts_view av JOIN ak_accounts a ON a.name = av.name ) <> 3 THEN
    RAISE EXCEPTION 'setup: hivemind_app.accounts_view does not show the 3 seeded HAF accounts';
  END IF;

  PERFORM hivemind_app.process_accounts_from_staging( 0 );

  SELECT string_agg( format( '%s: hivemind %s, HAF %s', a.name, ha.id, ak.a0 + a.haf_offset ), '; ' ORDER BY a.name ) INTO _mismatched
  FROM ak_accounts a CROSS JOIN ak_base ak
  LEFT JOIN hivemind_app.hive_accounts ha ON ha.name = a.name
  WHERE ha.id IS DISTINCT FROM ak.a0 + a.haf_offset;
  IF _mismatched IS NOT NULL THEN
    RAISE EXCEPTION 'a registered account does not take its HAF id: %', _mismatched;
  END IF;

  SELECT string_agg( format( '%s: hivemind %s, HAF %s', ha.name, ha.id, av.id ), '; ' ORDER BY ha.name ) INTO _mismatched
  FROM hivemind_app.hive_accounts ha JOIN hivemind_app.accounts_view av ON av.name = ha.name
  WHERE ha.id <> av.id;
  IF _mismatched IS NOT NULL THEN
    RAISE EXCEPTION 'hive_accounts ids differ from HAF''s: %', _mismatched;
  END IF;
END
$$;

INSERT INTO hivemind_app.hive_permlink_data ( permlink ) VALUES ( 'ak-post' );
INSERT INTO hivemind_app.hive_category_data ( category ) VALUES ( 'ak-cat' );
INSERT INTO hivemind_app.hive_posts ( id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth,
                                      block_num, block_num_created, pending_payout, total_vote_weight )
SELECT p.id, p.id, 0, ( SELECT id FROM hivemind_app.hive_accounts WHERE name = 'ak-second' ),
       ( SELECT id FROM hivemind_app.hive_permlink_data WHERE permlink = 'ak-post' ),
       ( SELECT id FROM hivemind_app.hive_category_data WHERE category = 'ak-cat' ),
       hivemind_app.head_block_time(), 0, ak.b0 + 3, ak.b0 + 3, 10, 100
FROM ( SELECT nextval( pg_get_serial_sequence( 'hivemind_app.hive_posts', 'id' ) )::INT AS id ) p, ak_base ak;
INSERT INTO hivemind_app.hive_votes ( post_id, voter_id, author_id, permlink_id, weight, rshares, vote_percent, last_update, block_num, is_effective )
SELECT hp.id, ( SELECT id FROM hivemind_app.hive_accounts WHERE name = 'ak-third' ), hp.author_id, hp.permlink_id,
       100, 1000, 10000, hivemind_app.head_block_time(), hp.block_num, TRUE
FROM hivemind_app.hive_posts hp
WHERE hp.permlink_id = ( SELECT id FROM hivemind_app.hive_permlink_data WHERE permlink = 'ak-post' );

DO $$
DECLARE
  _author hivemind_endpoints.pending_author_rewards;
  _curation hivemind_endpoints.pending_curation_rewards;
  _name TEXT;
BEGIN
  _author = hivemind_endpoints.get_account_pending_author_rewards( 'ak-second' );
  IF _author.pending_post_count <> 1 OR _author.gross_reward_basis->>'amount' = '0' THEN
    RAISE EXCEPTION 'pending author rewards of ak-second: expected its pending post, got %', row_to_json( _author );
  END IF;
  _curation = hivemind_endpoints.get_account_pending_curation_rewards( 'ak-third' );
  IF _curation.pending_vote_count <> 1 OR _curation.curation_reward_basis->'total'->>'amount' = '0' THEN
    RAISE EXCEPTION 'pending curation rewards of ak-third: expected its pending vote, got %', row_to_json( _curation );
  END IF;
  FOREACH _name IN ARRAY ARRAY['ak-first', 'ak-third'] LOOP
    _author = hivemind_endpoints.get_account_pending_author_rewards( _name );
    IF _author.pending_post_count <> 0 THEN
      RAISE EXCEPTION 'pending author rewards of %, who wrote no post: got %', _name, row_to_json( _author );
    END IF;
  END LOOP;
  FOREACH _name IN ARRAY ARRAY['ak-first', 'ak-second'] LOOP
    _curation = hivemind_endpoints.get_account_pending_curation_rewards( _name );
    IF _curation.pending_vote_count <> 0 THEN
      RAISE EXCEPTION 'pending curation rewards of %, who cast no vote: got %', _name, row_to_json( _curation );
    END IF;
  END LOOP;
END
$$;

ROLLBACK;
\echo account keyspace: registered accounts take HAF ids, and pending rewards read the posts and votes of the account itself
