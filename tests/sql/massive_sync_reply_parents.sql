-- process_posts_from_staging over one batch in which replies and their parents are
-- deleted and re-created, against the same ops applied one block at a time (as live
-- sync does) and against the rows the chain creates: every reply exists, and every
-- reply row's parent (and root, depth) is the parent row live at the reply's own op.
-- Seeds its own accounts and _ops_staging rows in a transaction it rolls back, so it
-- runs on any installed hivemind schema, including an empty chain:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/massive_sync_reply_parents.sql
--
-- rp-a's posts sort before rp-m's replies, rp-z's after them:
--   p1  a reply deleted and re-created under it, then the post deleted (no re-create);
--   p2  a reply re-created under its first row, then the post deleted and re-created
--       and the reply re-created under the new row;
--   p3  as p2, but the post is deleted again and the reply never re-created;
--   p4  deleted and re-created, then a first reply (with comment_options) and a reply
--       to that reply;
--   p6  (rp-z) a reply deleted, the post deleted and re-created, the reply re-created.

\set ON_ERROR_STOP 1
BEGIN;

INSERT INTO hivemind_app.hive_accounts (name, created_at)
VALUES ('rp-a', '2016-06-01'), ('rp-m', '2016-06-01'), ('rp-n', '2016-06-01'), ('rp-z', '2016-06-01');

-- C: comment, D: delete_comment, O: comment_options (percent_hbd 0)
CREATE TEMP TABLE rp_ops (block_num INT, op CHAR, author TEXT, permlink TEXT, parent_author TEXT, parent_permlink TEXT);
INSERT INTO rp_ops VALUES
  (100, 'C', 'rp-a', 'p1', '', 'rp-cat'),
  (101, 'C', 'rp-m', 'r1', 'rp-a', 'p1'),
  (102, 'D', 'rp-m', 'r1', NULL, NULL),
  (103, 'C', 'rp-m', 'r1', 'rp-a', 'p1'),
  (104, 'D', 'rp-m', 'r1', NULL, NULL),
  (105, 'D', 'rp-a', 'p1', NULL, NULL),

  (110, 'C', 'rp-a', 'p2', '', 'rp-cat'),
  (111, 'C', 'rp-m', 'r2', 'rp-a', 'p2'),
  (112, 'D', 'rp-m', 'r2', NULL, NULL),
  (113, 'C', 'rp-m', 'r2', 'rp-a', 'p2'),
  (114, 'D', 'rp-m', 'r2', NULL, NULL),
  (115, 'D', 'rp-a', 'p2', NULL, NULL),
  (116, 'C', 'rp-a', 'p2', '', 'rp-cat'),
  (117, 'C', 'rp-m', 'r2', 'rp-a', 'p2'),

  (120, 'C', 'rp-a', 'p3', '', 'rp-cat'),
  (121, 'C', 'rp-m', 'r3', 'rp-a', 'p3'),
  (122, 'D', 'rp-m', 'r3', NULL, NULL),
  (123, 'C', 'rp-m', 'r3', 'rp-a', 'p3'),
  (124, 'D', 'rp-m', 'r3', NULL, NULL),
  (125, 'D', 'rp-a', 'p3', NULL, NULL),
  (126, 'C', 'rp-a', 'p3', '', 'rp-cat'),
  (127, 'D', 'rp-a', 'p3', NULL, NULL),

  (130, 'C', 'rp-a', 'p4', '', 'rp-cat'),
  (131, 'D', 'rp-a', 'p4', NULL, NULL),
  (132, 'C', 'rp-a', 'p4', '', 'rp-cat'),
  (133, 'C', 'rp-m', 'r4', 'rp-a', 'p4'),
  (134, 'C', 'rp-n', 'r5', 'rp-m', 'r4'),
  (135, 'O', 'rp-m', 'r4', NULL, NULL),

  (140, 'C', 'rp-z', 'p6', '', 'rp-cat'),
  (141, 'C', 'rp-m', 'r6', 'rp-z', 'p6'),
  (142, 'D', 'rp-m', 'r6', NULL, NULL),
  (143, 'D', 'rp-z', 'p6', NULL, NULL),
  (144, 'C', 'rp-z', 'p6', '', 'rp-cat'),
  (145, 'C', 'rp-m', 'r6', 'rp-z', 'p6');

CREATE TEMP VIEW rp_staged AS
SELECT o.block_num::BIGINT * 10 AS id, o.block_num,
  '2016-06-03'::TIMESTAMP + o.block_num * INTERVAL '3 seconds' AS block_date,
  CASE o.op WHEN 'C' THEN 1 WHEN 'D' THEN 17 ELSE 19 END::SMALLINT AS op_type_id,
  CASE o.op
    WHEN 'C' THEN jsonb_build_object('author', o.author, 'permlink', o.permlink,
      'parent_author', o.parent_author, 'parent_permlink', o.parent_permlink,
      'title', '', 'body', 'body of ' || o.permlink, 'json_metadata', '{}')
    WHEN 'D' THEN jsonb_build_object('author', o.author, 'permlink', o.permlink)
    ELSE jsonb_build_object('author', o.author, 'permlink', o.permlink, 'percent_hbd', 0,
      'allow_votes', true, 'allow_curation_rewards', true, 'extensions', '[]'::jsonb,
      'max_accepted_payout', '{"amount": "1000000000", "precision": 3, "nai": "@@000000013"}'::jsonb)
  END AS val
FROM rp_ops o;

CREATE FUNCTION pg_temp.rp_post(_id INT) RETURNS TEXT LANGUAGE sql STABLE AS $$
  SELECT ha.name || '/' || hpd.permlink || '@' || hp.block_num_created
  FROM hivemind_app.hive_posts hp
  JOIN hivemind_app.hive_accounts ha ON ha.id = hp.author_id
  JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
  WHERE hp.id = _id AND _id <> 0  -- 0: no parent (a root post)
$$;

-- The elements of one jsonb array missing from the other, either way.
CREATE FUNCTION pg_temp.rp_diff(_got JSONB, _want JSONB) RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
  SELECT concat_ws(E'\n',
    (SELECT string_agg('got:  ' || g::TEXT, E'\n') FROM jsonb_array_elements(_got) g WHERE NOT _want @> jsonb_build_array(g)),
    (SELECT string_agg('want: ' || w::TEXT, E'\n') FROM jsonb_array_elements(_want) w WHERE NOT _got @> jsonb_build_array(w)))
$$;

-- Rows are named author/permlink@block_num_created: ids differ between the two runs.
CREATE TEMP VIEW rp_state AS
SELECT pg_temp.rp_post(hp.id) AS post, hp.counter_deleted, hp.depth,
  pg_temp.rp_post(hp.parent_id) AS parent, pg_temp.rp_post(hp.root_id) AS root,
  hp.block_num, hp.percent_hbd, hcd.category
FROM hivemind_app.hive_posts hp
JOIN hivemind_app.hive_accounts ha ON ha.id = hp.author_id
LEFT JOIN hivemind_app.hive_category_data hcd ON hcd.id = hp.category_id
WHERE ha.name LIKE 'rp-_';

CREATE TEMP TABLE rp_results (block_num INT, post_id INT, is_new_post BOOLEAN, parent_id INT, depth SMALLINT);
-- Named in a later statement than the one inserting them: rp_post would not see the rows yet.
CREATE TEMP VIEW rp_named_results AS
SELECT r.block_num, pg_temp.rp_post(r.post_id) AS post, r.is_new_post, pg_temp.rp_post(r.parent_id) AS parent, r.depth
FROM rp_results r;

SAVEPOINT massive;

TRUNCATE hivemind_app._ops_staging;
INSERT INTO hivemind_app._ops_staging (id, block_num, block_date, op_type_id, val)
SELECT id, block_num, block_date, op_type_id, val FROM rp_staged;
INSERT INTO rp_results
SELECT r.block_num, r.post_id, r.is_new_post, r.parent_id, r.depth
FROM hivemind_app.process_posts_from_staging(2147483647) r;

SELECT (SELECT jsonb_agg(to_jsonb(s) ORDER BY s.post) FROM rp_state s) AS massive_state,
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.block_num, r.post) FROM rp_named_results r) AS massive_results
\gset

ROLLBACK TO SAVEPOINT massive;

-- psql does not substitute variables inside the DO body
SELECT set_config('rp.massive_state', :'massive_state', true),
  set_config('rp.massive_results', :'massive_results', true) \gset ignored_

DO $$
DECLARE
  _block INT;
  _live_state JSONB;
  _live_results JSONB;
  _massive_state JSONB := current_setting('rp.massive_state')::JSONB;
  _massive_results JSONB := current_setting('rp.massive_results')::JSONB;
  _expected JSONB;
  _orphans TEXT;
BEGIN
  FOR _block IN SELECT DISTINCT block_num FROM rp_ops ORDER BY 1 LOOP
    TRUNCATE hivemind_app._ops_staging;
    INSERT INTO hivemind_app._ops_staging (id, block_num, block_date, op_type_id, val)
    SELECT id, block_num, block_date, op_type_id, val FROM rp_staged WHERE block_num = _block;
    INSERT INTO rp_results
    SELECT r.block_num, r.post_id, r.is_new_post, r.parent_id, r.depth
    FROM hivemind_app.process_posts_from_staging(2147483647) r;
  END LOOP;
  SELECT jsonb_agg(to_jsonb(s) ORDER BY s.post) INTO _live_state FROM rp_state s;
  SELECT jsonb_agg(to_jsonb(r) ORDER BY r.block_num, r.post) INTO _live_results FROM rp_named_results r;

  -- post, counter_deleted, depth, parent, root, block_num (the delete's for a deleted row)
  SELECT jsonb_agg(jsonb_build_object('post', e.post, 'counter_deleted', e.counter_deleted,
      'depth', e.depth, 'parent', e.parent, 'root', e.root, 'block_num', e.block_num,
      'percent_hbd', e.percent_hbd, 'category', 'rp-cat') ORDER BY e.post)
  INTO _expected
  FROM (VALUES
    ('rp-a/p1@100', 1, 0, NULL, 'rp-a/p1@100', 105, 10000),
    ('rp-m/r1@101', 1, 1, 'rp-a/p1@100', 'rp-a/p1@100', 102, 10000),
    ('rp-m/r1@103', 2, 1, 'rp-a/p1@100', 'rp-a/p1@100', 104, 10000),
    ('rp-a/p2@110', 1, 0, NULL, 'rp-a/p2@110', 115, 10000),
    ('rp-a/p2@116', 0, 0, NULL, 'rp-a/p2@116', 116, 10000),
    ('rp-m/r2@111', 1, 1, 'rp-a/p2@110', 'rp-a/p2@110', 112, 10000),
    ('rp-m/r2@113', 2, 1, 'rp-a/p2@110', 'rp-a/p2@110', 114, 10000),
    ('rp-m/r2@117', 0, 1, 'rp-a/p2@116', 'rp-a/p2@116', 117, 10000),
    ('rp-a/p3@120', 1, 0, NULL, 'rp-a/p3@120', 125, 10000),
    ('rp-a/p3@126', 2, 0, NULL, 'rp-a/p3@126', 127, 10000),
    ('rp-m/r3@121', 1, 1, 'rp-a/p3@120', 'rp-a/p3@120', 122, 10000),
    ('rp-m/r3@123', 2, 1, 'rp-a/p3@120', 'rp-a/p3@120', 124, 10000),
    ('rp-a/p4@130', 1, 0, NULL, 'rp-a/p4@130', 131, 10000),
    ('rp-a/p4@132', 0, 0, NULL, 'rp-a/p4@132', 132, 10000),
    ('rp-m/r4@133', 0, 1, 'rp-a/p4@132', 'rp-a/p4@132', 133, 0),
    ('rp-n/r5@134', 0, 2, 'rp-m/r4@133', 'rp-a/p4@132', 134, 10000),
    ('rp-z/p6@140', 1, 0, NULL, 'rp-z/p6@140', 143, 10000),
    ('rp-z/p6@144', 0, 0, NULL, 'rp-z/p6@144', 144, 10000),
    ('rp-m/r6@141', 1, 1, 'rp-z/p6@140', 'rp-z/p6@140', 142, 10000),
    ('rp-m/r6@145', 0, 1, 'rp-z/p6@144', 'rp-z/p6@144', 145, 10000)
  ) e (post, counter_deleted, depth, parent, root, block_num, percent_hbd);

  IF _live_state IS DISTINCT FROM _expected THEN
    RAISE EXCEPTION E'block-by-block hive_posts differ from the chain''s rows:\n%', pg_temp.rp_diff(_live_state, _expected);
  END IF;
  IF _massive_state IS DISTINCT FROM _expected THEN
    RAISE EXCEPTION E'one-batch hive_posts differ from the chain''s rows:\n%', pg_temp.rp_diff(_massive_state, _expected);
  END IF;

  -- One result per comment op, naming the row it created and that row's parent.
  IF _massive_results IS DISTINCT FROM _live_results THEN
    RAISE EXCEPTION E'one-batch results differ from block-by-block ones:\n%', pg_temp.rp_diff(_massive_results, _live_results);
  END IF;
  IF jsonb_array_length(_live_results) <> (SELECT count(*) FROM rp_ops WHERE op = 'C')
     OR EXISTS (
       SELECT 1 FROM jsonb_to_recordset(_live_results) r (block_num INT, post TEXT, is_new_post BOOLEAN)
       WHERE NOT r.is_new_post OR r.post NOT LIKE '%@' || r.block_num
     ) THEN
    RAISE EXCEPTION 'expected one new-post result per comment op, for the row it created: %', _live_results;
  END IF;

  -- The issue's detection query, on this batch's rows.
  SELECT string_agg(pg_temp.rp_post(c.id), ', ') INTO _orphans
  FROM hivemind_app.hive_posts c
  JOIN hivemind_app.hive_posts p ON p.id = c.parent_id
  JOIN hivemind_app.hive_accounts ha ON ha.id = c.author_id
  WHERE ha.name LIKE 'rp-_' AND c.counter_deleted = 0 AND c.depth > 0 AND p.counter_deleted > 0;
  IF _orphans IS NOT NULL THEN
    RAISE EXCEPTION 'live replies under a deleted parent row: %', _orphans;
  END IF;
END
$$;

ROLLBACK;
