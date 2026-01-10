-- Test function to verify SQL files are reloaded during build_schema
-- If this function returns the expected value, setup_runtime_code() is working
DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.sql_reload_test_marker;
CREATE FUNCTION hivemind_postgrest_utilities.sql_reload_test_marker()
RETURNS TEXT
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
  -- Change this value to test if SQL changes are picked up
  RETURN 'SQL_RELOAD_TEST_2026_01_09_V1';
END
$$;
