-- _post_batch is installed out of autovacuum, so its pg_class.reltuples is never set
-- from a vacuum that found it near-empty, and the posts phase's joins of a
-- hive_posts insert's RETURNING to it are planned from its current size. Runs on any
-- installed hivemind schema:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/post_batch_autovacuum_off.sql

\set ON_ERROR_STOP 1
BEGIN;

DO $$
BEGIN
  ASSERT (SELECT 'autovacuum_enabled=false' = ANY (c.reloptions)
          FROM pg_class c WHERE c.oid = 'hivemind_app._post_batch'::regclass),
    format('_post_batch is not out of autovacuum: reloptions %s',
           (SELECT c.reloptions FROM pg_class c WHERE c.oid = 'hivemind_app._post_batch'::regclass));
END
$$;

ROLLBACK;
