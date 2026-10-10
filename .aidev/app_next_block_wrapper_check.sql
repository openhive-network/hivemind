-- Applies scripts/ci/wrapper_for_app_next_block.sql twice to the stack's HAF and
-- checks the wrapper, inside one transaction that is rolled back.
--   psql -X -v ON_ERROR_STOP=1 -f .aidev/app_next_block_wrapper_check.sql
\set QUIET on
BEGIN;

\ir ../scripts/ci/wrapper_for_app_next_block.sql

DO $$
BEGIN
    ASSERT to_regprocedure('hive.app_next_block_haf(hive.contexts_group, boolean, integer)') IS NOT NULL,
        'HAF''s app_next_block was not renamed to app_next_block_haf';
    ASSERT (SELECT prosrc FROM pg_proc WHERE oid = 'hive.app_next_block(hive.contexts_group, boolean, integer)'::regprocedure)
           LIKE '%hive.app_next_block_haf(%',
        'the 3-argument hive.app_next_block does not delegate to app_next_block_haf';
    ASSERT has_function_privilege('hive_applications_group', 'hive.app_next_block(hive.contexts_group, boolean, integer)', 'EXECUTE'),
        'hive_applications_group cannot execute the wrapper';
END
$$;

CREATE TEMP TABLE applied_once AS
SELECT 'hive.app_next_block(hive.contexts_group, boolean, integer)'::regprocedure::oid AS wrapper_oid,
       'hive.app_next_block_haf(hive.contexts_group, boolean, integer)'::regprocedure::oid AS haf_oid,
       (SELECT prosrc FROM pg_proc WHERE oid = 'hive.app_next_block_haf(hive.contexts_group, boolean, integer)'::regprocedure) AS haf_src;

\ir ../scripts/ci/wrapper_for_app_next_block.sql

DO $$
BEGIN
    ASSERT (SELECT 'hive.app_next_block(hive.contexts_group, boolean, integer)'::regprocedure::oid = wrapper_oid
                AND 'hive.app_next_block_haf(hive.contexts_group, boolean, integer)'::regprocedure::oid = haf_oid
                AND (SELECT prosrc FROM pg_proc WHERE oid = haf_oid) = haf_src
            FROM applied_once),
        're-applying the wrapper changed hive.app_next_block or app_next_block_haf';
END
$$;

-- The cap, with HAF's range and the context's current block stubbed.
CREATE OR REPLACE FUNCTION hive.app_next_block_haf( _context_names hive.contexts_group, _wait BOOLEAN = TRUE, _block_limit INT = NULL )
    RETURNS hive.blocks_range LANGUAGE sql
AS $$ SELECT NULLIF(current_setting('wrapper_check.range'), '')::hive.blocks_range $$;
CREATE OR REPLACE FUNCTION hive.app_get_current_block_num( _contexts hive.contexts_group )
    RETURNS INTEGER LANGUAGE sql
AS $$ SELECT current_setting('wrapper_check.current_block')::INT $$;

CREATE FUNCTION pg_temp.next_range( _current_block INT, _range TEXT )
    RETURNS TEXT LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM set_config('wrapper_check.current_block', _current_block::TEXT, TRUE);
    PERFORM set_config('wrapper_check.range', COALESCE(_range, ''), TRUE);
    RETURN hive.app_next_block( ARRAY['hivemind_app']::hive.contexts_group, FALSE, NULL )::TEXT;
END
$$;

DO $$
DECLARE
    __got TEXT;
BEGIN
    __got := pg_temp.next_range( 0, '(1,5000024)' );
    ASSERT __got = '(1,4999979)', format('below the cap: (1,5000024) gave %s, expected (1,4999979)', __got);
    __got := pg_temp.next_range( 4000000, '(4000001,4001000)' );
    ASSERT __got = '(4000001,4001000)', format('below the cap: (4000001,4001000) gave %s', __got);
    __got := pg_temp.next_range( 4999979, '(4999980,5000024)' );
    ASSERT __got = '(4999980,5000024)', format('at the cap: (4999980,5000024) gave %s', __got);
    __got := pg_temp.next_range( 0, NULL );
    ASSERT __got IS NULL, format('no range gave %s', __got);
END
$$;

ROLLBACK;
\echo app_next_block wrapper: applied twice, delegates, caps at 4999979
