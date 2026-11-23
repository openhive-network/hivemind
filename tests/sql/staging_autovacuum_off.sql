-- The staging tables whose joins a stale estimate turns quadratic (_post_batch,
-- _vote_batch, _vote_upsert), and _ops_staging, which every load analyzes, are installed
-- out of autovacuum, so their pg_class.reltuples and statistics are never set from an
-- analyze or vacuum of some earlier fill. So are the tables pipelined massive sync hands
-- a batch to Stage B in (set_stage_b_handoff(TRUE)), also once hand_off_to_stage_b has
-- traded the names of _ops_staging and _ops_staging_b, which keep the indexes named after
-- them. Runs on any installed hivemind schema:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/staging_autovacuum_off.sql

\set ON_ERROR_STOP 1
BEGIN;

DO $$
DECLARE
  _table TEXT;
  _reloptions TEXT[];
BEGIN
  FOREACH _table IN ARRAY ARRAY['_post_batch', '_vote_batch', '_vote_upsert', '_ops_staging'] LOOP
    SELECT c.reloptions INTO _reloptions
    FROM pg_class c WHERE c.oid = format('hivemind_app.%I', _table)::regclass;
    ASSERT 'autovacuum_enabled=false' = ANY (_reloptions),
      format('%s is not out of autovacuum: reloptions %s', _table, _reloptions);
  END LOOP;
END
$$;

SELECT hivemind_app.set_stage_b_handoff(TRUE);
SELECT hivemind_app.hand_off_to_stage_b();

DO $$
DECLARE
  _table TEXT;
  _reloptions TEXT[];
  _indexes TEXT[];
BEGIN
  FOREACH _table IN ARRAY ARRAY['_ops_staging', '_ops_staging_b', '_post_results_b', '_deleted_posts_b'] LOOP
    SELECT c.reloptions INTO _reloptions
    FROM pg_class c WHERE c.oid = format('hivemind_app.%I', _table)::regclass AND c.relkind = 'r';
    ASSERT 'autovacuum_enabled=false' = ANY (_reloptions),
      format('%s is not a table out of autovacuum: reloptions %s', _table, _reloptions);
  END LOOP;
  FOREACH _table IN ARRAY ARRAY['_ops_staging', '_ops_staging_b'] LOOP
    SELECT array_agg(i.indexname::TEXT ORDER BY i.indexname) INTO _indexes
    FROM pg_indexes i WHERE i.schemaname = 'hivemind_app' AND i.tablename = _table;
    ASSERT _indexes = ARRAY[_table || '_block_num_id_idx', _table || '_op_type_id_idx'],
      format('%s has the indexes %s', _table, _indexes);
  END LOOP;
END
$$;

ROLLBACK;
