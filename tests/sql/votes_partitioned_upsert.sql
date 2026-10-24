-- The votes phase split across upsert workers (prepare_votes_from_staging, then
-- upsert_votes_partition for each partition) against the single-connection
-- process_votes_from_staging, on the same staged ops. Seeds its own accounts, posts,
-- votes and _ops_staging rows in a transaction it rolls back, so it runs on any
-- installed hivemind schema, including an empty chain:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/votes_partitioned_upsert.sql
--
-- The batch has votes and effective_comment_vote ops on six posts (all three
-- partitions of three), repeated votes, a vote on an unknown post, a vote cast before
-- its post was recreated, a known vote from an earlier block (num_changes grows) and
-- one from a later block (a replayed batch: num_changes kept).

\set ON_ERROR_STOP 1
BEGIN;

INSERT INTO hivemind_app.hive_accounts (name, created_at)
SELECT 'pv-v' || lpad(i::TEXT, 2, '0'), '2016-06-01' FROM generate_series(1, 12) i ORDER BY i;
INSERT INTO hivemind_app.hive_accounts (name, created_at) VALUES ('pv-a1', '2016-06-01'), ('pv-a2', '2016-06-01');
INSERT INTO hivemind_app.hive_permlink_data (permlink)
SELECT 'pv-p' || i FROM generate_series(1, 7) i ORDER BY i;
INSERT INTO hivemind_app.hive_category_data (category) VALUES ('pv-cat');

-- pv-p1..pv-p6: alternate authors; pv-p6 recreated at block 205. pv-p7 has no post.
INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, block_num, block_num_created)
SELECT p.id, p.id, 0,
  (SELECT id FROM hivemind_app.hive_accounts WHERE name = CASE WHEN p.i % 2 = 1 THEN 'pv-a1' ELSE 'pv-a2' END),
  (SELECT id FROM hivemind_app.hive_permlink_data WHERE permlink = 'pv-p' || p.i),
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'pv-cat'),
  '2016-06-01', 0, 100, CASE WHEN p.i = 6 THEN 205 ELSE 100 END
FROM (
  SELECT i, nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id')) AS id FROM generate_series(1, 6) i
) p;

INSERT INTO hivemind_app.hive_votes (post_id, voter_id, author_id, permlink_id, weight, rshares, vote_percent, last_update, num_changes, block_num, is_effective)
SELECT hp.id, ha.id, hp.author_id, hp.permlink_id, 7, 700, 1000, '2016-06-02', 2, k.block_num, TRUE
FROM (VALUES ('pv-v01', 'pv-p1', 150), ('pv-v02', 'pv-p2', 300)) k (voter, permlink, block_num)
JOIN hivemind_app.hive_accounts ha ON ha.name = k.voter
JOIN hivemind_app.hive_permlink_data hpd ON hpd.permlink = k.permlink
JOIN hivemind_app.hive_posts hp ON hp.permlink_id = hpd.id;

TRUNCATE hivemind_app._ops_staging;
-- Every voter votes on every post except where (voter + post) % 3 = 0; voters 1-4 vote
-- twice; effective_comment_vote ops for the even voters (twice for voter 2).
INSERT INTO hivemind_app._ops_staging (id, block_num, block_date, op_type_id, val)
SELECT row_number() OVER (ORDER BY o.block_num, o.v, o.p, o.op_type_id, o.rep), o.block_num,
  '2016-06-03'::TIMESTAMP + o.block_num * INTERVAL '3 seconds', o.op_type_id,
  jsonb_build_object(
    'voter', 'pv-v' || lpad(o.v::TEXT, 2, '0'),
    'author', CASE WHEN o.p % 2 = 1 THEN 'pv-a1' ELSE 'pv-a2' END,
    'permlink', 'pv-p' || o.p,
    'weight', CASE WHEN o.op_type_id = 0 THEN 100 * o.v + o.rep ELSE 10 * o.v + o.rep END
  ) || CASE WHEN o.op_type_id = 72 THEN jsonb_build_object('rshares', 1000 * o.v + o.p + o.rep) ELSE '{}' END
FROM (
  SELECT v, p, 0 AS op_type_id, rep, 200 + rep * 5 + (v + p) % 4 AS block_num
  FROM generate_series(1, 12) v, generate_series(1, 7) p, generate_series(0, 1) rep
  WHERE (v + p) % 3 <> 0 AND (rep = 0 OR v <= 4)
  UNION ALL
  SELECT v, p, 72, rep, 201 + rep * 5 + (v + p) % 4
  FROM generate_series(2, 12, 2) v, generate_series(1, 6) p, generate_series(0, 1) rep
  WHERE (v + p) % 3 <> 0 AND (rep = 0 OR v = 2)
) o;

INSERT INTO hivemind_app._ops_staging (id, block_num, block_date, op_type_id, val)
VALUES (1000, 300, '2016-06-03', 0, '{"voter": "pv-v02", "author": "pv-a2", "permlink": "pv-p2", "weight": 55}');

-- The batch's hive_votes rows, ids relative to the sequence position before it.
CREATE TEMP VIEW pv_votes AS
SELECT hv.voter_id, hv.author_id, hv.permlink_id, hv.post_id, hv.weight, hv.rshares, hv.vote_percent,
  hv.last_update, hv.num_changes, hv.block_num, hv.is_effective,
  CASE WHEN hv.id > current_setting('pv.base')::BIGINT
    THEN 'new+' || (hv.id - current_setting('pv.base')::BIGINT)
    ELSE 'old ' || hv.id END AS id
FROM hivemind_app.hive_votes hv
JOIN hivemind_app.hive_accounts ha ON ha.id = hv.voter_id
WHERE ha.name LIKE 'pv-v%';

SAVEPOINT serial;

SELECT set_config('pv.base', nextval('hivemind_app.hive_votes_id_seq')::TEXT, true) \gset ignored_
SELECT hivemind_app.process_votes_from_staging(0) AS serial_count \gset
SELECT nextval('hivemind_app.hive_votes_id_seq') - current_setting('pv.base')::BIGINT AS serial_seq_used,
  (SELECT jsonb_agg(to_jsonb(v) ORDER BY v.voter_id, v.author_id, v.permlink_id) FROM pv_votes v) AS serial_rows
\gset

ROLLBACK TO SAVEPOINT serial;

-- psql does not substitute variables inside the DO body
SELECT set_config('pv.serial_count', :'serial_count', true),
  set_config('pv.serial_seq_used', :'serial_seq_used', true),
  set_config('pv.serial_rows', :'serial_rows', true) \gset ignored_

DO $$
DECLARE
  _base BIGINT := nextval('hivemind_app.hive_votes_id_seq');
  _counts INT[] := ARRAY[0, 0, 0];
  _seq_used BIGINT;
  _rows JSONB;
  _again JSONB;
  _part INT;
  _serial_count INT := current_setting('pv.serial_count')::INT;
  _serial_seq_used BIGINT := current_setting('pv.serial_seq_used')::BIGINT;
  _serial_rows JSONB := current_setting('pv.serial_rows')::JSONB;
BEGIN
  PERFORM set_config('pv.base', _base::TEXT, true);
  PERFORM hivemind_app.prepare_votes_from_staging();
  -- In an order other than the ids': partitions commit in any order.
  FOREACH _part IN ARRAY ARRAY[2, 0, 1] LOOP
    _counts[_part + 1] = hivemind_app.upsert_votes_partition(_part, 3);
  END LOOP;
  _seq_used = nextval('hivemind_app.hive_votes_id_seq') - _base;
  SELECT jsonb_agg(to_jsonb(v) ORDER BY v.voter_id, v.author_id, v.permlink_id) INTO _rows FROM pv_votes v;

  IF 0 = ANY(_counts) THEN
    RAISE EXCEPTION 'setup: every partition must have votes, got %', _counts;
  END IF;
  IF _counts[1] + _counts[2] + _counts[3] <> _serial_count THEN
    RAISE EXCEPTION 'partitions wrote % rows (%), the serial path %', _counts[1] + _counts[2] + _counts[3], _counts, _serial_count;
  END IF;
  IF _seq_used <> _serial_seq_used THEN
    RAISE EXCEPTION 'partitions advanced the hive_votes id sequence by %, the serial path by %', _seq_used, _serial_seq_used;
  END IF;
  IF _rows IS DISTINCT FROM _serial_rows THEN
    RAISE EXCEPTION E'hive_votes differs from the serial path:\npartitioned: %\nserial: %', _rows, _serial_rows;
  END IF;

  -- One id drawn per written row, the two known votes' included.
  IF _seq_used <> _serial_count + 1
     OR (SELECT count(*) FROM jsonb_array_elements(_rows) r WHERE r->>'id' LIKE 'new+%') <> _serial_count - 2 THEN
    RAISE EXCEPTION 'expected % ids drawn and % new rows, got % ids drawn: %', _serial_count, _serial_count - 2, _seq_used - 1, _rows;
  END IF;
  IF NOT _rows @> '[{"num_changes": 3, "block_num": 207, "rshares": 700, "vote_percent": 101}]' THEN
    RAISE EXCEPTION 'pv-v01/pv-p1 (known from block 150): expected num_changes 3 at block 207, got %', _rows;
  END IF;
  IF NOT _rows @> '[{"num_changes": 2, "block_num": 300, "vote_percent": 55}]' THEN
    RAISE EXCEPTION 'pv-v02/pv-p2 (known from block 300): expected num_changes 2 kept, got %', _rows;
  END IF;

  -- A deadlock retry runs committed partitions again: hive_votes must not change.
  FOREACH _part IN ARRAY ARRAY[0, 1, 2] LOOP
    IF hivemind_app.upsert_votes_partition(_part, 3) <> _counts[_part + 1] THEN
      RAISE EXCEPTION 'partition % rerun wrote a different row count', _part;
    END IF;
  END LOOP;
  SELECT jsonb_agg(to_jsonb(v) ORDER BY v.voter_id, v.author_id, v.permlink_id) INTO _again FROM pv_votes v;
  IF _again IS DISTINCT FROM _rows THEN
    RAISE EXCEPTION E'rerunning the partitions changed hive_votes:\nafter: %\nbefore: %', _again, _rows;
  END IF;
END
$$;

ROLLBACK;
