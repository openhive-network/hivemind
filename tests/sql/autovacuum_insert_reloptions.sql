-- The append-mostly tables' autovacuum insert thresholds, which keep their visibility
-- maps current for index-only scans, are installed, and survive massive sync's toggle
-- of autovacuum_enabled (DbState.disable/restore_autovacuum_after_massive_sync). Runs
-- in a transaction it rolls back, on any installed hivemind schema:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/autovacuum_insert_reloptions.sql

\set ON_ERROR_STOP 1
BEGIN;

CREATE TEMP VIEW insert_reloptions AS
SELECT t.relname,
       'autovacuum_vacuum_insert_scale_factor=0' = ANY (c.reloptions) AS scale_factor_set,
       'autovacuum_vacuum_insert_threshold=100000' = ANY (c.reloptions) AS threshold_set
FROM unnest(ARRAY['hive_votes', 'hive_post_data', 'hive_permlink_data', 'hive_post_tags', 'hive_feed_cache']) t(relname)
LEFT JOIN pg_class c ON c.oid = to_regclass('hivemind_app.' || t.relname);

DO $$
DECLARE
  _missing TEXT;
BEGIN
  SELECT string_agg(relname, ', ') INTO _missing FROM insert_reloptions WHERE NOT (scale_factor_set AND threshold_set) OR scale_factor_set IS NULL;
  ASSERT _missing IS NULL, format('autovacuum insert thresholds missing on %s', _missing);
END
$$;

ALTER TABLE hivemind_app.hive_post_data SET (autovacuum_enabled = off, toast.autovacuum_enabled = off);
ALTER TABLE hivemind_app.hive_post_data RESET (autovacuum_enabled, toast.autovacuum_enabled);

DO $$
BEGIN
  ASSERT (SELECT scale_factor_set AND threshold_set FROM insert_reloptions WHERE relname = 'hive_post_data'),
    'the autovacuum_enabled toggle of massive sync lost hive_post_data''s insert thresholds';
END
$$;

ROLLBACK;
