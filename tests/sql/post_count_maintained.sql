-- hive_accounts.post_count, which process_post_counts_from_staging keeps from what
-- process_posts_from_staging hands Stage B, against the count of the author's live
-- hive_posts rows, after one batch of all the ops (as massive sync
-- runs them) and after each block on its own (as live sync does), and through
-- hive_accounts_info_view, which bridge.get_profile(s) read. The ops create, edit,
-- delete, and delete and re-create posts. Seeds its own accounts and _ops_staging rows
-- in a transaction it rolls back, so it runs on any installed hivemind schema,
-- including an empty chain:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/post_count_maintained.sql

\set ON_ERROR_STOP 1
BEGIN;

INSERT INTO hivemind_app.hive_accounts (id, name, created_at)
SELECT (SELECT max(id) FROM hivemind_app.hive_accounts) + a.n, a.name, '2016-06-01'
FROM unnest(ARRAY['pc-a', 'pc-b', 'pc-c']) WITH ORDINALITY AS a(name, n);

-- C: comment (a create, or an edit of the live row), D: delete_comment
CREATE TEMP TABLE pc_ops (block_num INT, op CHAR, author TEXT, permlink TEXT, parent_author TEXT, parent_permlink TEXT);
INSERT INTO pc_ops VALUES
  (200, 'C', 'pc-a', 'p1', '', 'pc-cat'),
  (201, 'C', 'pc-a', 'p1', '', 'pc-cat'),
  (202, 'C', 'pc-b', 'r1', 'pc-a', 'p1'),
  (203, 'D', 'pc-b', 'r1', NULL, NULL),
  (204, 'C', 'pc-b', 'r1', 'pc-a', 'p1'),
  (205, 'C', 'pc-a', 'p2', '', 'pc-cat'),
  (206, 'D', 'pc-a', 'p2', NULL, NULL),
  (207, 'C', 'pc-a', 'p3', '', 'pc-cat'),
  (208, 'C', 'pc-c', 'p4', '', 'pc-cat'),
  (209, 'D', 'pc-c', 'p4', NULL, NULL);

CREATE TEMP VIEW pc_staged AS
SELECT o.block_num::BIGINT * 10 AS id, o.block_num,
  '2016-06-03'::TIMESTAMP + o.block_num * INTERVAL '3 seconds' AS block_date,
  CASE o.op WHEN 'C' THEN 1 ELSE 17 END::SMALLINT AS op_type_id,
  CASE o.op
    WHEN 'C' THEN jsonb_build_object('author', o.author, 'permlink', o.permlink,
      'parent_author', o.parent_author, 'parent_permlink', o.parent_permlink,
      'title', '', 'body', 'body of ' || o.permlink, 'json_metadata', '{}')
    ELSE jsonb_build_object('author', o.author, 'permlink', o.permlink)
  END AS val
FROM pc_ops o;

-- Per account: the column, the view's value and the count the view used to take.
CREATE TEMP VIEW pc_counts AS
SELECT ha.name, ha.post_count, hai.post_count AS view_post_count,
  (SELECT count(*) FROM hivemind_app.hive_posts hp WHERE hp.author_id = ha.id AND hp.counter_deleted = 0) AS live_posts
FROM hivemind_app.hive_accounts ha
JOIN hivemind_app.hive_accounts_info_view hai ON hai.id = ha.id
WHERE ha.name LIKE 'pc-_';

CREATE FUNCTION pg_temp.pc_check(_run TEXT) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
  _got JSONB;
  _want JSONB := '{"pc-a": 2, "pc-b": 1, "pc-c": 0}';
BEGIN
  SELECT jsonb_object_agg(c.name, c.post_count) INTO _got FROM pc_counts c;
  IF EXISTS (SELECT 1 FROM pc_counts c WHERE c.post_count <> c.live_posts OR c.view_post_count <> c.live_posts) THEN
    RAISE EXCEPTION '%: post_count differs from the live posts: %', _run,
      (SELECT jsonb_agg(to_jsonb(c)) FROM pc_counts c);
  END IF;
  IF _got IS DISTINCT FROM _want THEN
    RAISE EXCEPTION '%: post_count % , expected %', _run, _got, _want;
  END IF;
END
$$;

SAVEPOINT massive;

TRUNCATE hivemind_app._ops_staging;
INSERT INTO hivemind_app._ops_staging (id, block_num, block_date, op_type_id, val)
SELECT id, block_num, block_date, op_type_id, val FROM pc_staged;
SELECT count(*) FROM hivemind_app.process_posts_from_staging(2147483647) \gset ignored_
SELECT hivemind_app.process_post_counts_from_staging(200) \gset ignored_
SELECT pg_temp.pc_check('one batch') \gset ignored_

ROLLBACK TO SAVEPOINT massive;

DO $$
DECLARE
  _block INT;
BEGIN
  FOR _block IN SELECT DISTINCT block_num FROM pc_ops ORDER BY 1 LOOP
    TRUNCATE hivemind_app._ops_staging;
    INSERT INTO hivemind_app._ops_staging (id, block_num, block_date, op_type_id, val)
    SELECT id, block_num, block_date, op_type_id, val FROM pc_staged WHERE block_num = _block;
    PERFORM count(*) FROM hivemind_app.process_posts_from_staging(2147483647);
    PERFORM hivemind_app.process_post_counts_from_staging(_block);
    IF EXISTS (SELECT 1 FROM pc_counts c WHERE c.post_count <> c.live_posts) THEN
      RAISE EXCEPTION 'block %: post_count differs from the live posts: %', _block,
        (SELECT jsonb_agg(to_jsonb(c)) FROM pc_counts c);
    END IF;
  END LOOP;
  PERFORM pg_temp.pc_check('block by block');
END
$$;

ROLLBACK;
