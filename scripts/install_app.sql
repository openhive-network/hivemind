-- Script contains all ADMINISTRATIVE steps required to setup a target database for Hivemind App
DO $$
DECLARE
__version INT;
BEGIN
    --ASSERT EXISTS( SELECT 1 FROM information_schema.schemata WHERE schema_name = ':REPTRACKER_SCHEMA' )
    --    , 'Reputation tracker is not installed'
    --;

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
