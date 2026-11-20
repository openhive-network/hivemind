-- The staging tables whose joins a stale estimate turns quadratic (_post_batch,
-- _vote_batch, _vote_upsert), and _ops_staging, which every load analyzes, are installed
-- out of autovacuum, so their pg_class.reltuples and statistics are never set from an
-- analyze or vacuum of some earlier fill. Runs on any installed hivemind schema:
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

ROLLBACK;
