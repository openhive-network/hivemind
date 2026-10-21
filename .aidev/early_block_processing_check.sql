-- On the installed hivemind, emulates hived replaying with psql-massive-index-policy =
-- keep-monotonic (hive.disable_indexes_of_irreversible('keep-monotonic'): the kept core
-- indexes stay, the deferred ones are dropped) and checks, inside one transaction that is
-- rolled back, that
--   - hivemind_app opted in to early block processing, so HAF hands it the dumped blocks
--     while hive.is_instance_ready() is false;
--   - hivemind's block reads (load_ops_staging) run with every deferred index missing;
--   - its stage stays massive after it caught up with the irreversible head, because the
--     stage is measured against the estimated chain head, until hived enters LIVE;
--   - its notification and payout windows count every dumped block as old, and go back
--     to the irreversible-relative estimate once HAF is ready (the drop-all case).
-- Needs an empty HAF (no blocks), as .aidev/test-stack.compose.yml starts it.
--   psql -X -v ON_ERROR_STOP=1 -f .aidev/early_block_processing_check.sql
\set QUIET on
BEGIN;
SET LOCAL statement_timeout = '120s';

DO $$
BEGIN
    ASSERT ( SELECT early_block_processing FROM hafd.contexts WHERE name = 'hivemind_app' ),
        'hivemind_app did not opt in to early block processing';
    ASSERT NOT EXISTS ( SELECT 1 FROM hafd.blocks ), 'the check needs a HAF database without blocks';
    ASSERT hive.is_instance_ready(), 'HAF must be ready before the emulated replay';
END
$$;

SELECT hive.disable_fk_of_irreversible();
SELECT hive.disable_indexes_of_irreversible( 'keep-monotonic' );
SELECT hive.set_sync_state( 'REINDEX' );

-- hived dumps blocks 1..20, produced in 2016 like the start of mainnet
INSERT INTO hafd.blocks
SELECT b, ( '\xBADD' || lpad( b::TEXT, 2, '0' ) )::bytea, '\xCAFE20', '2016-06-22 19:10:25'::timestamp + b * INTERVAL '3 seconds',
       5, '\x4007', E'[]', '\x2157', 'STM65w', 1000, 1000, 1000000, 1000, 1000, 1000, 2000, 2000
FROM generate_series( 1, 20 ) AS b;
SELECT hive.end_massive_sync( 20 );

-- what hive.app_next_iteration does for hivemind (sync.py) while hived replays
SELECT hive.app_context_attach( ARRAY[ 'hivemind_app' ] );
CREATE TEMP TABLE delivered AS
SELECT * FROM hive.app_next_block( ARRAY[ 'hivemind_app' ]::hive.contexts_group, FALSE );

DO $$
DECLARE
    __delivered hive.blocks_range := ( SELECT ROW( first_block, last_block )::hive.blocks_range FROM delivered );
BEGIN
    ASSERT EXISTS ( SELECT 1 FROM hafd.indexes_constraints WHERE contexts @> ARRAY[0] AND massive_sync_class = 'defer' AND status = 'missing' ),
        'the emulated replay deferred no core index';
    ASSERT NOT EXISTS ( SELECT 1 FROM pg_indexes WHERE schemaname = 'hafd' AND indexname IN ( 'pk_hive_transactions', 'hive_operations_op_type_id_block_num', 'hive_account_operations_uq1' ) ),
        'deferred indexes are still there';
    ASSERT NOT hive.is_instance_ready(), 'HAF reports ready while its deferred indexes are missing';
    ASSERT hive.is_instance_ready_for_contexts( ARRAY[ 'hivemind_app' ] ), 'hivemind_app waits for the end of the replay';
    ASSERT __delivered.first_block = 1 AND __delivered.last_block = 20,
        format( 'HAF handed hivemind_app %s while hived replays, expected (1,20)', __delivered );

    PERFORM hive.analyze_stages( ARRAY[ 'hivemind_app' ], __delivered, hive.get_estimated_hive_head_block() );
    ASSERT hive.get_current_stage_name( 'hivemind_app' ) = 'MASSIVE_WITHOUT_INDEXES',
        format( 'hivemind_app starts the replay in stage %s, expected MASSIVE_WITHOUT_INDEXES',
                hive.get_current_stage_name( 'hivemind_app' ) );

    PERFORM hivemind_app.load_ops_staging( __delivered.first_block, __delivered.last_block );

    UPDATE hafd.contexts SET current_block_num = __delivered.last_block, loop.current_batch_end = __delivered.last_block
    WHERE name = 'hivemind_app';
    ASSERT hive.app_get_current_block_num( 'hivemind_app' ) = hive.app_get_irreversible_block( 'hivemind_app' ),
        'hivemind_app did not catch up with the irreversible head';
    ASSERT ( SELECT ( s.stage ).name FROM hive.get_current_stage( ARRAY[ 'hivemind_app' ] ) s ) = 'MASSIVE_WITHOUT_INDEXES',
        format( 'hivemind_app caught up with the replay gets stage %s, expected MASSIVE_WITHOUT_INDEXES',
                ( SELECT ( s.stage ).name FROM hive.get_current_stage( ARRAY[ 'hivemind_app' ] ) s ) );

    ASSERT hivemind_app.block_before_irreversible( '90 days' ) = 20,
        format( 'the notification window starts after block %s while hived replays 2016, expected 20',
                hivemind_app.block_before_irreversible( '90 days' ) );
    ASSERT hivemind_app.block_before_irreversible( '7 days' ) = 20,
        format( 'the safe cashout block is %s while hived replays 2016, expected 20',
                hivemind_app.block_before_irreversible( '7 days' ) );
END
$$;

-- hived enters LIVE before it restores the deferred indexes; HAF then measures the stage
-- against the irreversible head, which is why sync.py waits for hive.is_instance_ready()
-- before it finalizes the massive sync
SELECT hive.set_sync_state( 'LIVE' );
DO $$
BEGIN
    ASSERT NOT hive.is_instance_ready() AND hive.is_instance_ready_for_contexts( ARRAY[ 'hivemind_app' ] ),
        'expected HAF ready for hivemind_app but not ready while it restores its indexes';
    ASSERT ARRAY( SELECT DISTINCT ( s.stage ).name::TEXT FROM hive.get_current_stage( ARRAY[ 'hivemind_app' ] ) s ) = ARRAY[ 'live' ],
        'HAF no longer offers the live stage before its index restore; revisit SyncHiveDb._wait_while_haf_restores_indexes';
END
$$;

-- the restore finished: HAF is ready, as it is for every block with the drop-all policy
UPDATE hafd.indexes_constraints SET status = 'created' WHERE contexts @> ARRAY[0];

DO $$
BEGIN
    ASSERT hive.is_instance_ready(), 'HAF is not ready after the emulated restore';
    ASSERT hivemind_app.block_before_irreversible( '90 days' ) = 20 - 90 * 24 * 1200,
        format( 'the notification window of a ready HAF starts after block %s, expected the irreversible block - 90 days',
                hivemind_app.block_before_irreversible( '90 days' ) );
    ASSERT hivemind_app.block_before_irreversible( '7 days' ) = 20 - 7 * 24 * 1200,
        format( 'the safe cashout block of a ready HAF is %s, expected the irreversible block - 7 days',
                hivemind_app.block_before_irreversible( '7 days' ) );
END
$$;

ROLLBACK;
\echo early block processing: hivemind_app gets blocks while hived replays and stays in massive sync
