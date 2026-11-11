-- recalculate_all_posts_votes_and_children run again over its own result writes no
-- hive_posts row, and run over rows whose vote aggregates or `children` are stale
-- rewrites exactly those rows, to the same values as the first run. A finalization
-- re-run after an interruption finds hive_posts' indexes restored, and a row it
-- rewrote would get a new entry in each of them. Seeds its own accounts, posts and
-- votes in a transaction it rolls back, so it runs on any installed hivemind schema,
-- including an empty chain:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/recalculate_votes_children_rerun.sql
--
-- rc-p1  a root post with a vote and two replies, rc-r1 (with a vote) and rc-r2;
-- rc-p2  a root post with a vote and no reply;
-- rc-p3  a root post without votes or replies.

\set ON_ERROR_STOP 1
BEGIN;

INSERT INTO hivemind_app.hive_accounts (name, created_at) VALUES ('rc-author', '2016-06-01'), ('rc-voter', '2016-06-01');
INSERT INTO hivemind_app.hive_permlink_data (permlink) VALUES ('rc-p1'), ('rc-p2'), ('rc-p3'), ('rc-r1'), ('rc-r2');
INSERT INTO hivemind_app.hive_category_data (category) VALUES ('rc-cat');

CREATE TEMP TABLE rc_posts (permlink TEXT, id INT, parent TEXT);
INSERT INTO rc_posts
SELECT t.permlink, nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id')), t.parent
FROM (VALUES ('rc-p1', NULL), ('rc-p2', NULL), ('rc-p3', NULL), ('rc-r1', 'rc-p1'), ('rc-r2', 'rc-p1')) AS t(permlink, parent)
ORDER BY t.parent NULLS FIRST, t.permlink;

INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, block_num, block_num_created)
SELECT rp.id, COALESCE(parent.id, rp.id), COALESCE(parent.id, 0),
  (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'rc-author'),
  hpd.id,
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'rc-cat'),
  '2016-06-01', (CASE WHEN rp.parent IS NULL THEN 0 ELSE 1 END), 1, 1
FROM rc_posts rp
JOIN hivemind_app.hive_permlink_data hpd ON hpd.permlink = rp.permlink
LEFT JOIN rc_posts parent ON parent.permlink = rp.parent
ORDER BY rp.id;

INSERT INTO hivemind_app.hive_votes (post_id, voter_id, author_id, permlink_id, weight, rshares, vote_percent, last_update, block_num, is_effective)
SELECT hp.id, (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'rc-voter'), hp.author_id, hp.permlink_id, 1, v.rshares, 10000, '2016-06-02', 1, TRUE
FROM (VALUES ('rc-p1', 4242), ('rc-p2', -17), ('rc-r1', 99)) AS v(permlink, rshares)
JOIN rc_posts rp ON rp.permlink = v.permlink
JOIN hivemind_app.hive_posts hp ON hp.id = rp.id;

CREATE TEMP VIEW rc_state AS
SELECT rp.permlink, hp.ctid AS row_ctid, hp.children, hp.abs_rshares, hp.vote_rshares, hp.total_votes, hp.net_votes, hp.sc_hot, hp.sc_trend
FROM rc_posts rp JOIN hivemind_app.hive_posts hp ON hp.id = rp.id;

CREATE FUNCTION pg_temp.rc_rewritten(_before TEXT) RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
  _r TEXT;
BEGIN
  EXECUTE format(
    'SELECT string_agg(s.permlink, '','' ORDER BY s.permlink) FROM rc_state s JOIN %I b USING (permlink) WHERE s.row_ctid != b.row_ctid',
    _before)
  INTO _r;
  RETURN COALESCE(_r, '');
END;
$$;

DO $$ BEGIN PERFORM hivemind_app.recalculate_all_posts_votes_and_children(); END $$;

DO $$
DECLARE
  _bad RECORD;
BEGIN
  FOR _bad IN
    SELECT s.*, e.*
    FROM rc_state s
    JOIN hivemind_app.hive_posts hp ON hp.id = (SELECT id FROM rc_posts WHERE permlink = s.permlink)
    JOIN (VALUES
      ('rc-p1', 2, 4242::NUMERIC, 4242::NUMERIC, 1::BIGINT, 1::BIGINT, TRUE),
      ('rc-p2', 0, 17, -17, 1, -1, TRUE),
      ('rc-p3', 0, 0, 0, 0, 0, FALSE),
      ('rc-r1', 0, 99, 99, 1, 1, FALSE),
      ('rc-r2', 0, 0, 0, 0, 0, FALSE)
    ) AS e(e_permlink, e_children, e_abs, e_rshares, e_total, e_net, e_ranked) ON e.e_permlink = s.permlink
    WHERE (s.children, s.abs_rshares, s.vote_rshares, s.total_votes, s.net_votes)
            IS DISTINCT FROM (e.e_children, e.e_abs, e.e_rshares, e.e_total, e.e_net)
       OR (e.e_ranked AND (s.sc_hot, s.sc_trend) IS DISTINCT FROM
             (hivemind_app.calculate_hot(e.e_rshares, hp.created_at), hivemind_app.calculate_trending(e.e_rshares, hp.created_at)))
       OR (NOT e.e_ranked AND (s.sc_hot, s.sc_trend) IS DISTINCT FROM (0::REAL, 0::REAL))
  LOOP
    RAISE EXCEPTION 'first run: % has %, expected %', _bad.permlink, row(_bad.children, _bad.abs_rshares, _bad.vote_rshares, _bad.total_votes, _bad.net_votes, _bad.sc_hot, _bad.sc_trend), row(_bad.e_children, _bad.e_abs, _bad.e_rshares, _bad.e_total, _bad.e_net, _bad.e_ranked);
  END LOOP;
END;
$$;

CREATE TEMP TABLE rc_first AS SELECT * FROM rc_state;

DO $$ BEGIN PERFORM hivemind_app.recalculate_all_posts_votes_and_children(); END $$;

DO $$
BEGIN
  IF pg_temp.rc_rewritten('rc_first') != '' THEN
    RAISE EXCEPTION 'rerun over its own result rewrote %', pg_temp.rc_rewritten('rc_first');
  END IF;
END;
$$;

UPDATE hivemind_app.hive_posts SET children = 7 WHERE id = (SELECT id FROM rc_posts WHERE permlink = 'rc-p1');
UPDATE hivemind_app.hive_posts SET vote_rshares = 0, sc_hot = 0 WHERE id = (SELECT id FROM rc_posts WHERE permlink = 'rc-p2');
UPDATE hivemind_app.hive_posts SET net_votes = 5 WHERE id = (SELECT id FROM rc_posts WHERE permlink = 'rc-r1');
CREATE TEMP TABLE rc_stale AS SELECT * FROM rc_state;

DO $$ BEGIN PERFORM hivemind_app.recalculate_all_posts_votes_and_children(); END $$;

DO $$
DECLARE
  _diff TEXT;
BEGIN
  IF pg_temp.rc_rewritten('rc_stale') != 'rc-p1,rc-p2,rc-r1' THEN
    RAISE EXCEPTION 'rerun over stale rows rewrote "%", expected "rc-p1,rc-p2,rc-r1"', pg_temp.rc_rewritten('rc_stale');
  END IF;

  SELECT string_agg(s.permlink, ',' ORDER BY s.permlink) INTO _diff
  FROM rc_state s JOIN rc_first f USING (permlink)
  WHERE (s.children, s.abs_rshares, s.vote_rshares, s.total_votes, s.net_votes, s.sc_hot, s.sc_trend)
        IS DISTINCT FROM (f.children, f.abs_rshares, f.vote_rshares, f.total_votes, f.net_votes, f.sc_hot, f.sc_trend);
  IF _diff IS NOT NULL THEN
    RAISE EXCEPTION 'rerun over stale rows left % different from the first run', _diff;
  END IF;
END;
$$;

ROLLBACK;
