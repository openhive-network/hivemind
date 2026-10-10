-- Applies scripts/ci/wrapper_for_app_next_block.sql twice to the stack's HAF and
-- checks the wrappers, inside one transaction that is rolled back.
--   psql -X -v ON_ERROR_STOP=1 -f .aidev/app_next_block_wrapper_check.sql
\set QUIET on
BEGIN;

CREATE TEMP TABLE haf_original AS
SELECT prosrc AS head_estimate_src
FROM pg_proc
WHERE oid = COALESCE( to_regprocedure('hive.get_estimated_hive_head_block_haf()'),
                      'hive.get_estimated_hive_head_block()'::regprocedure );

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
    ASSERT (SELECT prosrc FROM pg_proc WHERE oid = 'hive.get_estimated_hive_head_block_haf()'::regprocedure)
           = (SELECT head_estimate_src FROM haf_original),
        'HAF''s get_estimated_hive_head_block was not preserved as get_estimated_hive_head_block_haf';
    ASSERT (SELECT prosrc FROM pg_proc WHERE oid = 'hive.get_estimated_hive_head_block()'::regprocedure)
           LIKE '%hive.get_irreversible_head_block()%',
        'hive.get_estimated_hive_head_block does not return the irreversible head';
    ASSERT NOT EXISTS (
            SELECT 1 FROM pg_roles r
            WHERE has_function_privilege( r.oid, 'hive.get_estimated_hive_head_block()', 'EXECUTE' )
               <> has_function_privilege( r.oid, 'hive.get_estimated_hive_head_block_haf()', 'EXECUTE' ) ),
        'the get_estimated_hive_head_block wrapper''s EXECUTE grants differ from HAF''s function';
END
$$;

CREATE TEMP TABLE applied_once AS
SELECT 'hive.app_next_block(hive.contexts_group, boolean, integer)'::regprocedure::oid AS wrapper_oid,
       'hive.app_next_block_haf(hive.contexts_group, boolean, integer)'::regprocedure::oid AS haf_oid,
       (SELECT prosrc FROM pg_proc WHERE oid = 'hive.app_next_block_haf(hive.contexts_group, boolean, integer)'::regprocedure) AS haf_src,
       'hive.get_estimated_hive_head_block()'::regprocedure::oid AS head_wrapper_oid,
       'hive.get_estimated_hive_head_block_haf()'::regprocedure::oid AS head_haf_oid;

\ir ../scripts/ci/wrapper_for_app_next_block.sql

DO $$
BEGIN
    ASSERT (SELECT 'hive.app_next_block(hive.contexts_group, boolean, integer)'::regprocedure::oid = wrapper_oid
                AND 'hive.app_next_block_haf(hive.contexts_group, boolean, integer)'::regprocedure::oid = haf_oid
                AND (SELECT prosrc FROM pg_proc WHERE oid = haf_oid) = haf_src
            FROM applied_once),
        're-applying the wrapper changed hive.app_next_block or app_next_block_haf';
    ASSERT (SELECT 'hive.get_estimated_hive_head_block()'::regprocedure::oid = head_wrapper_oid
                AND 'hive.get_estimated_hive_head_block_haf()'::regprocedure::oid = head_haf_oid
                AND (SELECT prosrc FROM pg_proc WHERE oid = head_haf_oid) = (SELECT head_estimate_src FROM haf_original)
            FROM applied_once),
        're-applying the wrapper changed hive.get_estimated_hive_head_block or get_estimated_hive_head_block_haf';
END
$$;

-- The head estimate, with HAF's irreversible head stubbed.
CREATE OR REPLACE FUNCTION hive.get_irreversible_head_block()
    RETURNS INTEGER LANGUAGE sql
AS $$ SELECT 5000024 $$;

DO $$
BEGIN
    ASSERT hive.get_estimated_hive_head_block() = 5000024,
        format('get_estimated_hive_head_block gave %s, expected the irreversible head 5000024',
               hive.get_estimated_hive_head_block());
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
\echo get_estimated_hive_head_block wrapper: applied twice, original preserved, grants match, returns the irreversible head
