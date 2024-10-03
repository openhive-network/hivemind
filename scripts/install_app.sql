-- Script contains all ADMINISTRATIVE steps required to setup a target database for Hivemind App
CREATE OR REPLACE FUNCTION hivemind_check_reptracker( _reptracker_schema TEXT )
RETURNS VOID
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    ASSERT EXISTS( SELECT 1 FROM information_schema.schemata WHERE schema_name = _reptracker_schema )
        , 'Reputation tracker is not installed';
END;
$$;

SELECT hivemind_check_reptracker( :'REPTRACKER_SCHEMA' );
DROP FUNCTION hivemind_check_reptracker;

DO $$
DECLARE
__version INT;
BEGIN
  SELECT CURRENT_SETTING('server_version_num')::INT INTO __version;

  EXECUTE 'ALTER DATABASE '||current_database()||' SET join_collapse_limit TO 16';
  EXECUTE 'ALTER DATABASE '||current_database()||' SET from_collapse_limit TO 16';
  EXECUTE 'GRANT CREATE ON DATABASE '||current_database()||' TO hivemind';

  IF __version >= 120000 THEN
    RAISE NOTICE 'Disabling a JIT optimization on the current database level...';
    EXECUTE 'ALTER DATABASE '||current_database()||' SET jit TO False';
  END IF;
END
$$;
