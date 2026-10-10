-- Caps the block ranges HAF hands out at 4999979 until a context reaches it, so
-- the 5M mock data is synced massively up to 4999979 and 4999980..5000024 goes
-- through the live path. hive.app_next_iteration calls the 3-argument
-- hive.app_next_block, which is wrapped here.
--
-- Truncating the range only makes HAF re-analyze stages at 4999980; the stage
-- is picked from the distance to hive.get_estimated_hive_head_block(), which
-- extrapolates from the head block's timestamp to now(). The mock blocks date
-- from 2016, so that estimate is ~100M blocks ahead and live is never reached.
-- It is wrapped too, to return the irreversible head (5000024).
--
-- Idempotent: HAF's functions are renamed to *_haf only the first time.
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

DO $$
BEGIN
    IF to_regprocedure('hive.get_estimated_hive_head_block_haf()') IS NULL THEN
        ALTER FUNCTION hive.get_estimated_hive_head_block() RENAME TO get_estimated_hive_head_block_haf;
    END IF;
END
$$;

CREATE OR REPLACE FUNCTION hive.get_estimated_hive_head_block()
    RETURNS INTEGER
    LANGUAGE plpgsql
    STABLE
AS
$BODY$
BEGIN
    RETURN hive.get_irreversible_head_block();
END;
$BODY$;

-- Same EXECUTE grants as HAF's function (a NULL ACL means the defaults).
DO $$
DECLARE
    __grantee TEXT;
BEGIN
    REVOKE ALL ON FUNCTION hive.get_estimated_hive_head_block() FROM PUBLIC;
    FOR __grantee IN
        SELECT CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE acl.grantee::regrole::TEXT END
        FROM pg_proc p, aclexplode( COALESCE( p.proacl, acldefault( 'f', p.proowner ) ) ) acl
        WHERE p.oid = 'hive.get_estimated_hive_head_block_haf()'::regprocedure
          AND acl.privilege_type = 'EXECUTE'
    LOOP
        EXECUTE format( 'GRANT EXECUTE ON FUNCTION hive.get_estimated_hive_head_block() TO %s', __grantee );
    END LOOP;
END
$$;
