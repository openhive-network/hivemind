-- Caps the block ranges HAF hands out at 4999979 until a context reaches it, so
-- the 5M mock data is synced massively up to 4999979 and 4999980..5000024 goes
-- through the live path. hive.app_next_iteration calls the 3-argument
-- hive.app_next_block, which is wrapped here.
--
-- Idempotent: HAF's function is renamed to app_next_block_haf only the first time.
-- If neither name exists (HAF changed the signature), the ALTER fails.
DO $$
BEGIN
    IF to_regprocedure('hive.app_next_block_haf(hive.contexts_group, boolean, integer)') IS NULL THEN
        ALTER FUNCTION hive.app_next_block( hive.contexts_group, BOOLEAN, INT ) RENAME TO app_next_block_haf;
    END IF;
END
$$;

CREATE OR REPLACE FUNCTION hive.app_next_block( _context_names hive.contexts_group, _wait BOOLEAN = TRUE, _block_limit INT = NULL )
    RETURNS hive.blocks_range
    LANGUAGE plpgsql
    VOLATILE
AS
$BODY$
DECLARE
    __last_block_for_massive CONSTANT INT = 4999979;
    __result hive.blocks_range;
BEGIN
    __result := hive.app_next_block_haf( _context_names, _wait, _block_limit );

    IF __result IS NOT NULL
       AND hive.app_get_current_block_num( _context_names ) < __last_block_for_massive
       AND __result.last_block > __last_block_for_massive
    THEN
        __result.last_block := __last_block_for_massive;
    END IF;

    RETURN __result;
END;
$BODY$;

REVOKE EXECUTE ON FUNCTION hive.app_next_block( hive.contexts_group, BOOLEAN, INT ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hive.app_next_block( hive.contexts_group, BOOLEAN, INT ) TO hive_applications_group;
