-- The rewrite of hive_votes in post order (DbState._order_hive_votes_by_post: the
-- order index from its registered command, then CLUSTER on it) keeps every row,
-- stores them in (post_id, voter_id) order, and leaves the table with the same valid
-- indexes and constraints and the index marked as the clustering one, the mark a
-- restart reads to skip the rewrite.
-- Seeds its own accounts, posts and votes, in an order the rewrite has to change, in
-- a transaction it rolls back, so it runs on any installed hivemind schema, including
-- an empty chain:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/order_hive_votes_cluster.sql

\set ON_ERROR_STOP 1
BEGIN;

INSERT INTO hivemind_app.hive_accounts (id, name, created_at)
SELECT (SELECT max(id) FROM hivemind_app.hive_accounts) + a.n, a.name, '2016-06-01'
FROM unnest(ARRAY['ov-author', 'ov-voter1', 'ov-voter2', 'ov-voter3']) WITH ORDINALITY AS a(name, n);
INSERT INTO hivemind_app.hive_permlink_data (permlink) VALUES ('ov-p1'), ('ov-p2'), ('ov-p3');
INSERT INTO hivemind_app.hive_category_data (category) VALUES ('ov-cat');

INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, block_num, block_num_created)
SELECT p.id, p.id, 0, (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'ov-author'), hpd.id,
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'ov-cat'), '2016-06-01', 0, 1, 1
FROM (
  SELECT hpd.permlink, nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id')) AS id
  FROM hivemind_app.hive_permlink_data hpd WHERE hpd.permlink LIKE 'ov-p_' ORDER BY hpd.permlink
) p
JOIN hivemind_app.hive_permlink_data hpd ON hpd.permlink = p.permlink;

-- Block order: each block's votes spread over the posts, the later posts first.
INSERT INTO hivemind_app.hive_votes (post_id, voter_id, author_id, permlink_id, weight, rshares, vote_percent, last_update, block_num, is_effective)
SELECT hp.id, ha.id, hp.author_id, hp.permlink_id, 1, 100 * v.block + v.post, 10000, '2016-06-02', v.block, TRUE
FROM (VALUES (1, 3, 'ov-voter3'), (1, 1, 'ov-voter2'), (2, 2, 'ov-voter3'), (2, 1, 'ov-voter1'),
             (3, 3, 'ov-voter1'), (3, 2, 'ov-voter2'), (4, 1, 'ov-voter3'), (4, 3, 'ov-voter2')) AS v(block, post, voter)
JOIN hivemind_app.hive_permlink_data hpd ON hpd.permlink = 'ov-p' || v.post
JOIN hivemind_app.hive_posts hp ON hp.permlink_id = hpd.id
JOIN hivemind_app.hive_accounts ha ON ha.name = v.voter
ORDER BY v.block, v.post DESC;

CREATE TEMP TABLE ov_rows AS SELECT * FROM hivemind_app.hive_votes;
CREATE TEMP VIEW ov_definitions AS
SELECT pg_get_indexdef(i.indexrelid) AS definition, pg_get_constraintdef(c.oid) AS constraint_definition
FROM pg_index i
LEFT JOIN pg_constraint c ON c.conindid = i.indexrelid AND c.conrelid = i.indrelid
WHERE i.indrelid = 'hivemind_app.hive_votes'::REGCLASS;
CREATE TEMP TABLE ov_definitions_before AS SELECT * FROM ov_definitions;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM (
      SELECT (post_id, voter_id) < lag((post_id, voter_id)) OVER (ORDER BY ctid) AS inverted FROM hivemind_app.hive_votes
    ) o WHERE o.inverted
  ) THEN
    RAISE EXCEPTION 'the seeded votes are in post order already, so the check measures nothing';
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS hive_votes_post_id_voter_id_idx ON hivemind_app.hive_votes (post_id, voter_id);
CLUSTER hivemind_app.hive_votes USING hive_votes_post_id_voter_id_idx;

DO $$
DECLARE
  _n BIGINT;
  _bad TEXT;
BEGIN
  SELECT count(*) INTO _n FROM (
    (SELECT * FROM hivemind_app.hive_votes EXCEPT ALL SELECT * FROM ov_rows)
    UNION ALL
    (SELECT * FROM ov_rows EXCEPT ALL SELECT * FROM hivemind_app.hive_votes)
  ) d;
  IF _n != 0 THEN
    RAISE EXCEPTION 'the rewrite changed % rows of hive_votes', _n;
  END IF;

  SELECT count(*) INTO _n FROM (
    SELECT (post_id, voter_id) < lag((post_id, voter_id)) OVER (ORDER BY ctid) AS inverted FROM hivemind_app.hive_votes
  ) o WHERE o.inverted;
  IF _n != 0 THEN
    RAISE EXCEPTION 'hive_votes is not in post order after the rewrite: % rows follow a greater (post_id, voter_id)', _n;
  END IF;

  SELECT string_agg(c.definition, '; ') INTO _bad FROM (
    (SELECT * FROM ov_definitions EXCEPT SELECT * FROM ov_definitions_before)
    UNION ALL
    (SELECT * FROM ov_definitions_before EXCEPT SELECT * FROM ov_definitions)
  ) c;
  IF _bad IS NOT NULL THEN
    RAISE EXCEPTION 'the rewrite changed hive_votes'' indexes or constraints: %', _bad;
  END IF;

  SELECT string_agg(i.indexrelid::REGCLASS::TEXT, ', ') INTO _bad
  FROM pg_index i WHERE i.indrelid = 'hivemind_app.hive_votes'::REGCLASS AND NOT (i.indisvalid AND i.indisready);
  IF _bad IS NOT NULL THEN
    RAISE EXCEPTION 'invalid indexes on hive_votes after the rewrite: %', _bad;
  END IF;

  IF NOT (SELECT indisclustered FROM pg_index WHERE indexrelid = 'hivemind_app.hive_votes_post_id_voter_id_idx'::REGCLASS) THEN
    RAISE EXCEPTION 'hive_votes_post_id_voter_id_idx is not marked as the clustering index';
  END IF;
END;
$$;

ROLLBACK;
