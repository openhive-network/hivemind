-- The votes, payouts and reblogs phases of one massive batch against the same blocks
-- processed one at a time, each after its own posts phase. Seeds its own accounts, posts, votes
-- and _ops_staging rows in a transaction it rolls back, so it runs on any installed
-- hivemind schema, including an empty chain:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/massive_batch_block_by_block.sql
--
-- Blocks 301-308 hold votes on a post deleted at block 305 (one cast after the
-- delete), on a post deleted at 303 and re-created at 304, repeated votes with and
-- without effective_comment_vote ops, a vote whose first block has no effective vote,
-- and payout ops on the deleted post and on a post paid out twice, a post reblogged
-- twice and one reblogged, unreblogged and reblogged twice more. Vote ids differ
-- between the runs, but must be in the same order (vote notification counters follow it).

\set ON_ERROR_STOP 1
BEGIN;

INSERT INTO hivemind_app.hive_accounts (name, created_at)
SELECT 'bb-' || n, '2016-06-01' FROM unnest(ARRAY['v1', 'v2', 'v3', 'v4', 'a']) n ORDER BY n;
INSERT INTO hivemind_app.hive_permlink_data (permlink)
SELECT 'bb-p' || i FROM generate_series(1, 4) i ORDER BY i;
INSERT INTO hivemind_app.hive_category_data (category) VALUES ('bb-cat');

CREATE TEMP TABLE bb_post (permlink TEXT, id INT);
INSERT INTO bb_post
SELECT p.permlink, nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id'))
FROM unnest(ARRAY['bb-p1', 'bb-p2', 'bb-p3', 'bb-p4', 'bb-p2-new']) WITH ORDINALITY p (permlink, i) ORDER BY i;

CREATE FUNCTION pg_temp.bb_insert_post(_permlink TEXT, _block INT) RETURNS VOID AS $$
    INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth,
                                         block_num, block_num_created, payout_at, cashout_time)
    SELECT bp.id, bp.id, 0,
      (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'bb-a'),
      (SELECT id FROM hivemind_app.hive_permlink_data WHERE permlink = split_part(_permlink, '-new', 1)),
      (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'bb-cat'),
      '2016-06-01', 0, _block, _block, '2016-06-08', '2016-06-08'
    FROM bb_post bp WHERE bp.permlink = _permlink;
$$ LANGUAGE sql;

SELECT pg_temp.bb_insert_post(p, 100) FROM unnest(ARRAY['bb-p1', 'bb-p2', 'bb-p3', 'bb-p4']) p;

-- bb-v2's vote on bb-p4 from an earlier batch
INSERT INTO hivemind_app.hive_votes (post_id, voter_id, author_id, permlink_id, weight, rshares, vote_percent, last_update, num_changes, block_num, is_effective)
SELECT hp.id, (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'bb-v2'), hp.author_id, hp.permlink_id,
  7, 700, 1000, '2016-06-02', 2, 150, TRUE
FROM hivemind_app.hive_posts hp WHERE hp.id = (SELECT id FROM bb_post WHERE permlink = 'bb-p4');

-- What the posts phase of a block does to these posts: delete bb-p2 at 303, re-create it
-- at 304, delete bb-p1 at 305 (as delete_hive_post does).
CREATE FUNCTION pg_temp.bb_posts_phase(_first INT, _last INT) RETURNS VOID AS $$
BEGIN
    IF 303 BETWEEN _first AND _last THEN
        UPDATE hivemind_app.hive_posts SET counter_deleted = 1, block_num = 303
        WHERE id = (SELECT id FROM bb_post WHERE permlink = 'bb-p2');
    END IF;
    IF 304 BETWEEN _first AND _last THEN
        PERFORM pg_temp.bb_insert_post('bb-p2-new', 304);
    END IF;
    IF 305 BETWEEN _first AND _last THEN
        UPDATE hivemind_app.hive_posts SET counter_deleted = 1, block_num = 305
        WHERE id = (SELECT id FROM bb_post WHERE permlink = 'bb-p1');
    END IF;
END
$$ LANGUAGE plpgsql;

-- (block, op type, voter, permlink, value): type 0 a vote (value its weight), 72 an
-- effective_comment_vote (value its weight and rshares), 51/53/61 payouts (value the amount),
-- 18 a reblog by voter (value 1) or its delete (value 0).
CREATE TEMP TABLE bb_ops (block_num INT, op_type_id SMALLINT, voter TEXT, permlink TEXT, v BIGINT);
INSERT INTO bb_ops VALUES
  -- bb-p1, deleted at 305: votes before it stay with the deleted post, the one after is dropped
  (302, 0, 'v1', 'bb-p1', 10000), (302, 72, 'v1', 'bb-p1', 11),
  (304, 0, 'v2', 'bb-p1', 5000),
  (306, 0, 'v3', 'bb-p1', 10000), (306, 72, 'v3', 'bb-p1', 12),
  -- bb-p2, deleted at 303 and re-created at 304
  (301, 0, 'v1', 'bb-p2', 10000), (301, 72, 'v1', 'bb-p2', 13),
  (302, 0, 'v2', 'bb-p2', 10000), (302, 72, 'v2', 'bb-p2', 14),
  (303, 0, 'v3', 'bb-p2', 10000), (303, 72, 'v3', 'bb-p2', 15),
  (306, 0, 'v1', 'bb-p2', 9000), (306, 72, 'v1', 'bb-p2', 16),
  -- bb-p3: blocks with one, none and two effective votes
  (301, 0, 'v1', 'bb-p3', 10000), (301, 72, 'v1', 'bb-p3', 17),
  (303, 0, 'v1', 'bb-p3', 8000),
  (305, 0, 'v1', 'bb-p3', 7000), (305, 72, 'v1', 'bb-p3', 18), (305, 72, 'v1', 'bb-p3', 19),
  (307, 0, 'v1', 'bb-p3', 6000), (307, 72, 'v1', 'bb-p3', 20),
  -- bb-p4: first block without an effective vote, for a known and for a new vote
  (302, 0, 'v2', 'bb-p4', 3000), (305, 0, 'v2', 'bb-p4', 4000), (305, 72, 'v2', 'bb-p4', 21),
  (302, 0, 'v4', 'bb-p4', 3000), (305, 0, 'v4', 'bb-p4', 4000), (305, 72, 'v4', 'bb-p4', 22),
  -- payouts (the effective votes above carry pending payouts): bb-p3 paid out at 304 and
  -- at 308, with an effective vote's pending payout between
  (304, 61, NULL, 'bb-p3', 0), (304, 51, NULL, 'bb-p3', 100), (304, 53, NULL, 'bb-p3', 1000),
  (308, 61, NULL, 'bb-p3', 0), (308, 51, NULL, 'bb-p3', 200), (308, 53, NULL, 'bb-p3', 2000),
  -- reblogs: one block at a time keeps the first of two, and the first after a delete
  (302, 18, 'v1', 'bb-p3', 1), (306, 18, 'v1', 'bb-p3', 1),
  (301, 18, 'v2', 'bb-p4', 1), (303, 18, 'v2', 'bb-p4', 0), (304, 18, 'v2', 'bb-p4', 1), (307, 18, 'v2', 'bb-p4', 1);

CREATE FUNCTION pg_temp.bb_stage(_first INT, _last INT) RETURNS VOID AS $$
    DELETE FROM hivemind_app._ops_staging;
    INSERT INTO hivemind_app._ops_staging (id, block_num, block_date, op_type_id, val)
    SELECT row_number() OVER (ORDER BY o.block_num, o.op_type_id, o.voter, o.permlink, o.v),
      o.block_num, '2016-06-03'::TIMESTAMP + o.block_num * INTERVAL '3 seconds', o.op_type_id,
      jsonb_build_object('author', 'bb-a', 'permlink', o.permlink) || CASE o.op_type_id
        WHEN 0 THEN jsonb_build_object('voter', 'bb-' || o.voter, 'weight', o.v)
        WHEN 72 THEN jsonb_build_object('voter', 'bb-' || o.voter, 'weight', o.v, 'rshares', 1000000 * o.v,
          'pending_payout', jsonb_build_object('amount', (100 * o.v)::TEXT, 'precision', 3, 'nai', '@@000000013'),
          'total_vote_weight', 10 * o.v)
        WHEN 51 THEN jsonb_build_object('hive_payout', jsonb_build_object('amount', o.v::TEXT),
          'hbd_payout', jsonb_build_object('amount', (2 * o.v)::TEXT), 'vesting_payout', jsonb_build_object('amount', (3 * o.v)::TEXT))
        WHEN 53 THEN jsonb_build_object('author_rewards', o.v,
          'total_payout_value', jsonb_build_object('amount', o.v::TEXT, 'precision', 3, 'nai', '@@000000013'),
          'curator_payout_value', jsonb_build_object('amount', (o.v / 2)::TEXT, 'precision', 3, 'nai', '@@000000013'),
          'beneficiary_payout_value', jsonb_build_object('amount', '0', 'precision', 3, 'nai', '@@000000013'))
        WHEN 18 THEN jsonb_build_object('id', 'reblog', 'required_auths', '[]'::jsonb,
          'required_posting_auths', jsonb_build_array('bb-' || o.voter),
          'json', jsonb_build_array('reblog', jsonb_build_object('account', 'bb-' || o.voter, 'author', 'bb-a',
            'permlink', o.permlink) || CASE WHEN o.v = 0 THEN '{"delete": "delete"}'::jsonb ELSE '{}'::jsonb END)::TEXT)
        ELSE '{}'::jsonb END
    FROM bb_ops o
    WHERE o.block_num BETWEEN _first AND _last;
$$ LANGUAGE sql;

-- The seeded votes and posts, ids replaced by natural keys and votes' by their order
CREATE FUNCTION pg_temp.bb_state() RETURNS JSONB AS $$
    SELECT jsonb_build_object(
      'votes', (SELECT jsonb_agg(to_jsonb(hv) - 'id' - 'post_id' - 'voter_id'
                                 || jsonb_build_object('voter', ha.name, 'post', bp.permlink) ORDER BY ha.name, bp.permlink)
                FROM (SELECT v.*, rank() OVER (ORDER BY v.id) AS id_order FROM hivemind_app.hive_votes v) hv
                JOIN hivemind_app.hive_accounts ha ON ha.id = hv.voter_id
                JOIN bb_post bp ON bp.id = hv.post_id),
      'posts', (SELECT jsonb_agg(jsonb_build_object('post', bp.permlink, 'counter_deleted', hp.counter_deleted,
                  'payout', hp.payout, 'pending_payout', hp.pending_payout, 'total_payout_value', hp.total_payout_value,
                  'curator_payout_value', hp.curator_payout_value, 'author_rewards', hp.author_rewards,
                  'author_rewards_hive', hp.author_rewards_hive, 'author_rewards_hbd', hp.author_rewards_hbd,
                  'author_rewards_vests', hp.author_rewards_vests, 'payout_at', hp.payout_at,
                  'last_payout_at', hp.last_payout_at, 'cashout_time', hp.cashout_time, 'is_paidout', hp.is_paidout,
                  'total_vote_weight', hp.total_vote_weight, 'last_payout_block', hp.last_payout_block) ORDER BY bp.permlink)
                FROM hivemind_app.hive_posts hp JOIN bb_post bp ON bp.id = hp.id),
      'reblogs', (SELECT jsonb_agg(jsonb_build_object('blogger', ha.name, 'post', bp.permlink,
                    'block_num', hr.block_num, 'created_at', hr.created_at) ORDER BY ha.name, bp.permlink)
                  FROM hivemind_app.hive_reblogs hr
                  JOIN hivemind_app.hive_accounts ha ON ha.id = hr.blogger_id
                  JOIN bb_post bp ON bp.id = hr.post_id));
$$ LANGUAGE sql;

CREATE FUNCTION pg_temp.bb_run(_first INT, _last INT, _blocks_per_batch INT) RETURNS JSONB AS $$
BEGIN
    FOR _batch_first IN _first.._last BY _blocks_per_batch LOOP
        PERFORM pg_temp.bb_posts_phase(_batch_first, LEAST(_batch_first + _blocks_per_batch - 1, _last));
        PERFORM pg_temp.bb_stage(_batch_first, LEAST(_batch_first + _blocks_per_batch - 1, _last));
        PERFORM hivemind_app.process_votes_from_staging(0);
        PERFORM hivemind_app.process_payouts_from_staging(0);
        PERFORM hivemind_app.process_reblogs_from_staging();
    END LOOP;
    RETURN pg_temp.bb_state();
END
$$ LANGUAGE plpgsql;

SAVEPOINT batch;
SELECT pg_temp.bb_run(301, 308, 8) AS batch_state \gset
ROLLBACK TO SAVEPOINT batch;
SELECT pg_temp.bb_run(301, 308, 3) AS three_block_state \gset
ROLLBACK TO SAVEPOINT batch;
SELECT pg_temp.bb_run(301, 308, 1) AS block_state \gset

CREATE FUNCTION pg_temp.bb_check(_batch JSONB, _three JSONB, _blocks JSONB) RETURNS VOID AS $$
BEGIN
    IF _batch IS DISTINCT FROM _blocks THEN
        RAISE EXCEPTION E'one batch differs from blocks processed one at a time:\nbatch:  %\nblocks: %', _batch, _blocks;
    END IF;
    IF _three IS DISTINCT FROM _blocks THEN
        RAISE EXCEPTION E'3-block batches differ from blocks processed one at a time:\nbatches: %\nblocks:  %', _three, _blocks;
    END IF;
    IF NOT _blocks->'votes' @> '[{"voter": "bb-v1", "post": "bb-p1", "block_num": 302},
                                {"voter": "bb-v2", "post": "bb-p1", "block_num": 304}]'
       OR _blocks->'votes' @> '[{"voter": "bb-v3", "post": "bb-p1"}]' THEN
        RAISE EXCEPTION 'bb-p1: expected the votes before its delete kept and the one after dropped, got %', _blocks->'votes';
    END IF;
    IF NOT _blocks->'votes' @> '[{"voter": "bb-v1", "post": "bb-p2-new", "num_changes": 1},
                                {"voter": "bb-v2", "post": "bb-p2"}]'
       OR _blocks->'votes' @> '[{"voter": "bb-v3"}]' THEN
        RAISE EXCEPTION 'bb-p2: expected bb-v1 on the re-created post, bb-v2 on the deleted one, no bb-v3, got %', _blocks->'votes';
    END IF;
    IF NOT _blocks->'votes' @> '[{"voter": "bb-v1", "post": "bb-p3", "num_changes": 4, "vote_percent": 6000}]' THEN
        RAISE EXCEPTION 'bb-p3: expected num_changes 4 (blocks 303, 305 twice, 307), got %', _blocks->'votes';
    END IF;
    IF NOT _blocks->'votes' @> '[{"voter": "bb-v4", "post": "bb-p4", "is_effective": false, "weight": 22, "num_changes": 1},
                                {"voter": "bb-v2", "post": "bb-p4", "is_effective": true, "weight": 21, "num_changes": 4}]' THEN
        RAISE EXCEPTION 'bb-p4: unexpected votes %', _blocks->'votes';
    END IF;
    IF _blocks->'reblogs' IS DISTINCT FROM '[{"blogger": "bb-v1", "post": "bb-p3", "block_num": 302, "created_at": "2016-06-03T00:15:06"},
                                           {"blogger": "bb-v2", "post": "bb-p4", "block_num": 304, "created_at": "2016-06-03T00:15:12"}]' THEN
        RAISE EXCEPTION 'expected the reblogs of blocks 302 and 304 (the first, and the first after the delete), got %', _blocks->'reblogs';
    END IF;
    IF NOT _blocks->'posts' @> '[{"post": "bb-p1", "counter_deleted": 1, "pending_payout": 1.100},
                                {"post": "bb-p3", "author_rewards": 3000, "is_paidout": true, "pending_payout": 0}]' THEN
        RAISE EXCEPTION 'unexpected payout state %', _blocks->'posts';
    END IF;
END
$$ LANGUAGE plpgsql;

SELECT pg_temp.bb_check(:'batch_state'::JSONB, :'three_block_state'::JSONB, :'block_state'::JSONB);

ROLLBACK;
