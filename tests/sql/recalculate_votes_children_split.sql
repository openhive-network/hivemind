-- The recompute finalization runs by post id ranges (prepare_posts_children, then
-- recalculate_posts_votes_and_children over disjoint ranges in any order) leaves every
-- hive_posts row's vote aggregates and `children` equal to the serial
-- recalculate_all_posts_votes_and_children's. So does a split run interrupted after
-- some of its ranges committed and then restarted from the beginning, and the restart
-- rewrites no row of the ranges that committed before the interruption. Seeds its own
-- accounts, posts and votes in a transaction it rolls back, so it runs on any
-- installed hivemind schema, including an empty chain:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/recalculate_votes_children_split.sql
--
-- rs-p1  a root post with a vote, a reply rs-r1 (with two votes) and a reply rs-r2,
--        which has a reply rs-r3;
-- rs-p2  a root post with a vote and no reply;
-- rs-p3  a root post without votes or replies.

\set ON_ERROR_STOP 1
BEGIN;

INSERT INTO hivemind_app.hive_accounts (id, name, created_at)
SELECT (SELECT max(id) FROM hivemind_app.hive_accounts) + a.n, a.name, '2016-06-01'
FROM unnest(ARRAY['rs-author', 'rs-voter1', 'rs-voter2']) WITH ORDINALITY AS a(name, n);
INSERT INTO hivemind_app.hive_permlink_data (permlink)
VALUES ('rs-p1'), ('rs-p2'), ('rs-p3'), ('rs-r1'), ('rs-r2'), ('rs-r3');
INSERT INTO hivemind_app.hive_category_data (category) VALUES ('rs-cat');

CREATE TEMP TABLE rs_posts (permlink TEXT, id INT, parent TEXT, depth INT);
INSERT INTO rs_posts
SELECT t.permlink, nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id')), t.parent, t.depth
FROM (VALUES ('rs-p1', NULL, 0), ('rs-p2', NULL, 0), ('rs-p3', NULL, 0),
             ('rs-r1', 'rs-p1', 1), ('rs-r2', 'rs-p1', 1), ('rs-r3', 'rs-r2', 2)) AS t(permlink, parent, depth)
ORDER BY t.depth, t.permlink;

INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, block_num, block_num_created)
SELECT rp.id, CASE WHEN rp.parent IS NULL THEN rp.id ELSE (SELECT r.id FROM rs_posts r WHERE r.permlink = 'rs-p1') END,
  COALESCE(parent.id, 0),
  (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'rs-author'),
  hpd.id,
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'rs-cat'),
  '2016-06-01', rp.depth, 1, 1
FROM rs_posts rp
JOIN hivemind_app.hive_permlink_data hpd ON hpd.permlink = rp.permlink
LEFT JOIN rs_posts parent ON parent.permlink = rp.parent
ORDER BY rp.id;

INSERT INTO hivemind_app.hive_votes (post_id, voter_id, author_id, permlink_id, weight, rshares, vote_percent, last_update, block_num, is_effective)
SELECT hp.id, (SELECT id FROM hivemind_app.hive_accounts WHERE name = v.voter), hp.author_id, hp.permlink_id, 1, v.rshares, 10000, '2016-06-02', 1, TRUE
FROM (VALUES ('rs-p1', 'rs-voter1', 4242), ('rs-p2', 'rs-voter1', -17), ('rs-r1', 'rs-voter1', 99), ('rs-r1', 'rs-voter2', -5))
  AS v(permlink, voter, rshares)
JOIN rs_posts rp ON rp.permlink = v.permlink
JOIN hivemind_app.hive_posts hp ON hp.id = rp.id;

-- Every row's recomputed columns, and the ctid that shows whether a run rewrote it.
CREATE TEMP VIEW rs_state AS
SELECT hp.id, hp.ctid AS row_ctid, hp.children, hp.abs_rshares, hp.vote_rshares, hp.total_votes, hp.net_votes, hp.sc_hot, hp.sc_trend
FROM hivemind_app.hive_posts hp;

CREATE FUNCTION pg_temp.rs_differences(_expected TEXT) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
  _n BIGINT;
BEGIN
  EXECUTE format(
    'SELECT count(*) FROM ('
    '  (SELECT id, children, abs_rshares, vote_rshares, total_votes, net_votes, sc_hot, sc_trend FROM rs_state'
    '   EXCEPT SELECT id, children, abs_rshares, vote_rshares, total_votes, net_votes, sc_hot, sc_trend FROM %1$I)'
    '  UNION ALL'
    '  (SELECT id, children, abs_rshares, vote_rshares, total_votes, net_votes, sc_hot, sc_trend FROM %1$I'
    '   EXCEPT SELECT id, children, abs_rshares, vote_rshares, total_votes, net_votes, sc_hot, sc_trend FROM rs_state)'
    ') d', _expected)
  INTO _n;
  RETURN _n;
END;
$$;

-- Stale values in the columns the recompute writes (a post's `children` when it has
-- children, its vote aggregates when it has votes), so that every run has rows to write.
CREATE FUNCTION pg_temp.rs_make_stale() RETURNS VOID LANGUAGE sql AS $$
  UPDATE hivemind_app.hive_posts hp SET children = hp.children + 9
  FROM rs_posts rp WHERE hp.id = rp.id AND rp.permlink IN ('rs-p1', 'rs-r2');
  UPDATE hivemind_app.hive_posts hp
  SET abs_rshares = 1, vote_rshares = 1, total_votes = 7, net_votes = 7, sc_hot = 1, sc_trend = 1
  FROM rs_posts rp WHERE hp.id = rp.id AND rp.permlink IN ('rs-p1', 'rs-p2', 'rs-r1');
$$;

-- Ranges that split the seeded posts: rs-p1 and its replies fall into different ranges.
CREATE TEMP TABLE rs_ranges AS
SELECT * FROM (VALUES
  (1, 0, (SELECT id FROM rs_posts WHERE permlink = 'rs-p2') - 1),
  (2, (SELECT id FROM rs_posts WHERE permlink = 'rs-p2'), (SELECT id FROM rs_posts WHERE permlink = 'rs-r2') - 1),
  (3, (SELECT id FROM rs_posts WHERE permlink = 'rs-r2'), 2147483647)
) AS r(n, first_id, last_id);

DO $$ BEGIN PERFORM hivemind_app.recalculate_all_posts_votes_and_children(); END $$;
CREATE TEMP TABLE rs_serial AS SELECT * FROM rs_state;

DO $$
DECLARE
  _bad TEXT;
BEGIN
  SELECT string_agg(format('%s: %s', rp.permlink, row(s.children, s.vote_rshares, s.total_votes, s.net_votes)), '; ')
  INTO _bad
  FROM rs_posts rp
  JOIN rs_serial s ON s.id = rp.id
  JOIN (VALUES ('rs-p1', 3, 4242::NUMERIC, 1::BIGINT, 1::BIGINT), ('rs-p2', 0, -17, 1, -1), ('rs-p3', 0, 0, 0, 0),
               ('rs-r1', 0, 94, 2, 0), ('rs-r2', 1, 0, 0, 0), ('rs-r3', 0, 0, 0, 0))
    AS e(permlink, children, rshares, total, net) ON e.permlink = rp.permlink
  WHERE (s.children, s.vote_rshares, s.total_votes, s.net_votes) IS DISTINCT FROM (e.children, e.rshares, e.total, e.net);
  IF _bad IS NOT NULL THEN
    RAISE EXCEPTION 'serial recompute: %', _bad;
  END IF;
END;
$$;

-- The split run, its ranges in reverse order.
SELECT pg_temp.rs_make_stale();
DO $$
BEGIN
  IF pg_temp.rs_differences('rs_serial') = 0 THEN
    RAISE EXCEPTION 'the stale rows equal the recomputed ones, so the check measures nothing';
  END IF;
END;
$$;
DO $$ BEGIN
  PERFORM hivemind_app.prepare_posts_children();
  PERFORM hivemind_app.recalculate_posts_votes_and_children(r.first_id, r.last_id) FROM rs_ranges r ORDER BY r.n DESC;
  TRUNCATE TABLE hivemind_app.__post_children;
END $$;

DO $$
BEGIN
  IF pg_temp.rs_differences('rs_serial') != 0 THEN
    RAISE EXCEPTION 'split recompute left % rows different from the serial one', pg_temp.rs_differences('rs_serial');
  END IF;
END;
$$;

-- Interrupted after its first range, then restarted from prepare_posts_children.
SELECT pg_temp.rs_make_stale();
DO $$ BEGIN
  PERFORM hivemind_app.prepare_posts_children();
  PERFORM hivemind_app.recalculate_posts_votes_and_children(r.first_id, r.last_id) FROM rs_ranges r WHERE r.n = 1;
END $$;
CREATE TEMP TABLE rs_interrupted AS SELECT * FROM rs_state;

DO $$ BEGIN
  PERFORM hivemind_app.prepare_posts_children();
  PERFORM hivemind_app.recalculate_posts_votes_and_children(r.first_id, r.last_id) FROM rs_ranges r ORDER BY r.n;
  TRUNCATE TABLE hivemind_app.__post_children;
END $$;

DO $$
DECLARE
  _rewritten TEXT;
BEGIN
  IF pg_temp.rs_differences('rs_serial') != 0 THEN
    RAISE EXCEPTION 'restarted split recompute left % rows different from the serial one', pg_temp.rs_differences('rs_serial');
  END IF;

  SELECT string_agg(rp.permlink, ',' ORDER BY rp.permlink) INTO _rewritten
  FROM rs_posts rp
  JOIN rs_ranges r ON r.n = 1 AND rp.id BETWEEN r.first_id AND r.last_id
  JOIN rs_state s ON s.id = rp.id
  JOIN rs_interrupted i ON i.id = rp.id
  WHERE s.row_ctid != i.row_ctid;
  IF _rewritten IS NOT NULL THEN
    RAISE EXCEPTION 'the restart rewrote % of the range that committed before the interruption', _rewritten;
  END IF;
END;
$$;

ROLLBACK;
