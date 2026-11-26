DROP FUNCTION IF EXISTS hivemind_app.copy_back_hive_votes;
--- Replaces hive_votes' rows by those of _sorted, a table of hive_votes' columns, in
--- _sorted's heap order. hive_votes' indexes and the constraints they back are dropped
--- for the copy and rebuilt from the copied heap after it, as CLUSTER rebuilds them,
--- instead of being maintained row by row; its other constraints (foreign keys) stay.
--- Returns the seconds the copy and the rebuild took.
---
--- DbState sorts hive_votes into _sorted with a parallel query and calls this in the
--- same transaction, so an interruption anywhere leaves hive_votes as it was.
CREATE OR REPLACE FUNCTION hivemind_app.copy_back_hive_votes(_sorted REGCLASS, OUT copy_seconds FLOAT, OUT rebuild_seconds FLOAT)
LANGUAGE 'plpgsql'
VOLATILE
AS
$BODY$
DECLARE
  __drop TEXT[];
  __rebuild TEXT[];
  __sql TEXT;
  __start TIMESTAMPTZ := clock_timestamp();
BEGIN
  -- A synchronized scan may start in the middle of _sorted's heap.
  SET LOCAL synchronize_seqscans = off;

  SELECT
      COALESCE(array_agg(CASE WHEN c.oid IS NULL
                           THEN format('DROP INDEX %s', i.indexrelid::REGCLASS)
                           ELSE format('ALTER TABLE hivemind_app.hive_votes DROP CONSTRAINT %I', c.conname)
                         END), '{}')
    , COALESCE(array_agg(CASE WHEN c.oid IS NULL
                           THEN pg_get_indexdef(i.indexrelid)
                           ELSE format('ALTER TABLE hivemind_app.hive_votes ADD CONSTRAINT %I %s', c.conname, pg_get_constraintdef(c.oid))
                         END), '{}')
  INTO __drop, __rebuild
  FROM pg_index i
  LEFT JOIN pg_constraint c
    ON c.conindid = i.indexrelid AND c.conrelid = i.indrelid AND c.contype IN ('p', 'u', 'x')
  WHERE i.indrelid = 'hivemind_app.hive_votes'::REGCLASS;

  FOREACH __sql IN ARRAY __drop LOOP
    EXECUTE __sql;
  END LOOP;

  TRUNCATE TABLE hivemind_app.hive_votes;
  EXECUTE format('INSERT INTO hivemind_app.hive_votes SELECT * FROM %s', _sorted);
  copy_seconds := extract(EPOCH FROM clock_timestamp() - __start);

  __start := clock_timestamp();
  FOREACH __sql IN ARRAY __rebuild LOOP
    EXECUTE __sql;
  END LOOP;
  rebuild_seconds := extract(EPOCH FROM clock_timestamp() - __start);

  RESET synchronize_seqscans;
END;

$BODY$
;
