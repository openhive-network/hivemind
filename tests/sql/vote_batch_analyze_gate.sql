-- prepare_votes_from_staging analyzes _vote_batch for a fill of staging_analyze_min_rows()
-- rows or more only when the connection has not analyzed one yet, or the fill is more
-- than twice or less than half the rows of the last one analyzed. The table's analyze
-- count tells whether a fill was analyzed. Seeds its own accounts and _ops_staging rows
-- in a transaction it rolls back, so it runs on any installed hivemind schema:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/vote_batch_analyze_gate.sql

\set ON_ERROR_STOP 1
BEGIN;

INSERT INTO hivemind_app.hive_accounts (id, name, created_at)
SELECT (SELECT max(id) FROM hivemind_app.hive_accounts) + a.n, a.name, '2016-06-01'
FROM unnest(ARRAY['vg-voter', 'vg-author']) WITH ORDINALITY AS a(name, n);

-- Whether a fill of _rows _vote_batch rows (one vote per block, on posts that do not
-- exist) is analyzed.
CREATE FUNCTION pg_temp.fill_analyzed(_rows INT) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE
  _before BIGINT;
BEGIN
  PERFORM pg_stat_clear_snapshot();
  _before := pg_stat_get_analyze_count('hivemind_app._vote_batch'::regclass);
  TRUNCATE hivemind_app._ops_staging, hivemind_app._vote_batch;
  INSERT INTO hivemind_app._ops_staging (id, block_num, block_date, op_type_id, val)
  SELECT g, g, '2016-06-03', 0,
    jsonb_build_object('voter', 'vg-voter', 'author', 'vg-author', 'permlink', 'vg-p' || g, 'weight', 100)
  FROM generate_series(1, _rows) g;
  PERFORM hivemind_app.prepare_votes_from_staging();
  PERFORM pg_stat_clear_snapshot();
  RETURN pg_stat_get_analyze_count('hivemind_app._vote_batch'::regclass) > _before;
END
$$;

DO $$
DECLARE
  _min INT := hivemind_app.staging_analyze_min_rows();
  _case RECORD;
  _analyzed BOOLEAN;
BEGIN
  -- As on a new connection.
  PERFORM set_config('hivemind.vote_batch_analyzed_rows', '', false);
  FOR _case IN
    SELECT * FROM (VALUES
      (1, _min - 1, FALSE),      -- below the minimum: never analyzed
      (2, 2 * _min, TRUE),       -- the connection's first fill
      (3, 4 * _min, FALSE),      -- twice the last one analyzed
      (4, _min, FALSE),          -- half of it
      (5, 4 * _min + 1, TRUE),   -- more than twice
      (6, 2 * _min + 1, FALSE),  -- not less than half of it
      (7, 2 * _min, TRUE)        -- less than half
    ) c (n, rows, analyzed)
    ORDER BY n
  LOOP
    _analyzed := pg_temp.fill_analyzed(_case.rows);
    ASSERT _analyzed = _case.analyzed,
      format('fill %s of %s rows: analyzed %s, expected %s', _case.n, _case.rows, _analyzed, _case.analyzed);
  END LOOP;
  ASSERT current_setting('hivemind.vote_batch_analyzed_rows') = (2 * _min)::TEXT,
    format('rows analyzed recorded as %s', current_setting('hivemind.vote_batch_analyzed_rows'));
END
$$;

ROLLBACK;
