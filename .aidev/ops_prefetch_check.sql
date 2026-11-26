-- On the installed hivemind, checks inside one transaction that is rolled back that the
-- prefetch of a massive batch's operations (hivemind_app.prefetch_ops_staging, run by the
-- hivemind role before HAF hands the range out)
--   - reads no block past HAF's consistent block, even when asked for more;
--   - loads into _ops_staging, through load_ops_staging_from_prefetch, the rows
--     load_ops_staging loads from the context's views once HAF has handed the range out,
--     for a range shorter than the one prefetched too;
--   - leaves the same rows in _ops_staging, in the same order, through
--     take_prefetched_ops_staging (the handoff tables' rename), with both tables keeping
--     their indexes, and refuses it without the handoff tables.
-- Needs an empty HAF (no blocks), as .aidev/test-stack.compose.yml starts it.
--   psql -X -v ON_ERROR_STOP=1 -f .aidev/ops_prefetch_check.sql
\set QUIET on
BEGIN;
SET LOCAL statement_timeout = '120s';

DO $$
BEGIN
    ASSERT NOT EXISTS ( SELECT 1 FROM hafd.blocks ), 'the check needs a HAF database without blocks';
END
$$;

SELECT hive.disable_fk_of_irreversible();

INSERT INTO hafd.blocks
SELECT b, ( '\xBADD' || lpad( b::TEXT, 2, '0' ) )::bytea, '\xCAFE20', '2016-06-22 19:10:25'::timestamp + b * INTERVAL '3 seconds',
       5, '\x4007', E'[]', '\x2157', 'STM65w', 1000, 1000, 1000000, 1000, 1000, 1000, 2000, 2000
FROM generate_series( 1, 30 ) AS b;

-- a HAF hived has not started on yet has no operation types
INSERT INTO hafd.operation_types ( id, name, is_virtual ) VALUES
    ( 0, 'hive::protocol::vote_operation', FALSE ),
    ( 2, 'hive::protocol::transfer_operation', FALSE ),
    ( 18, 'hive::protocol::custom_json_operation', FALSE ),
    ( 51, 'hive::protocol::author_reward_operation', TRUE )
ON CONFLICT DO NOTHING;

INSERT INTO hafd.custom_json_types ( custom_json_id ) VALUES ( 'follow' ), ( 'prefetch-check' ) ON CONFLICT DO NOTHING;

-- per block: a vote, a transfer (not staged), a follow custom_json, a custom_json of an id
-- hivemind ignores (not staged) and a virtual op (staged with its own block's date)
INSERT INTO hafd.operations ( id, trx_in_block, op_type_id, op_pos, body_value, custom_json_type_id )
SELECT hafd.operation_id( b, o.pos ), o.trx, o.op_type_id, o.pos,
       jsonb_build_object( 'block', b, 'pos', o.pos ),
       ( SELECT id FROM hafd.custom_json_types WHERE custom_json_id = o.custom_json_id )
FROM generate_series( 1, 30 ) AS b
CROSS JOIN ( VALUES ( 0, 0, 0, NULL ), ( 1, 0, 2, NULL ), ( 2, 0, 18, 'follow' ), ( 3, 0, 18, 'prefetch-check' ), ( 4, -1, 51, NULL ) )
    AS o ( pos, trx, op_type_id, custom_json_id );

-- HAF has dumped blocks 1..30, 25 of them consistent; hivemind_app was handed 11..20
UPDATE hafd.hive_state SET consistent_block = 25;
UPDATE hafd.contexts SET current_block_num = 20, irreversible_block = 25 WHERE name = 'hivemind_app';

SET LOCAL ROLE hivemind;

SELECT hivemind_app.load_ops_staging( 11, 20 );
CREATE TEMP TABLE loaded AS SELECT * FROM hivemind_app._ops_staging;

DO $$
DECLARE
    __loaded_last INT;
    __range INT[];
BEGIN
    ASSERT ( SELECT count(*) FROM loaded ) = 30,
        format( 'load_ops_staging(11, 20) staged %s operations, expected 30', ( SELECT count(*) FROM loaded ) );
    ASSERT ( SELECT block_date FROM loaded WHERE block_num = 11 AND op_type_id = 0 ) = '2016-06-22 19:10:25'::timestamp + 10 * INTERVAL '3 seconds',
        'load_ops_staging did not date a block''s vote with the previous block''s time';

    __loaded_last := hivemind_app.prefetch_ops_staging( 11, 40 );
    ASSERT __loaded_last = 25, format( 'prefetch_ops_staging(11, 40) loaded up to block %s, expected the consistent block 25', __loaded_last );
    ASSERT ( SELECT max( block_num ) FROM hivemind_app._ops_staging_next ) = 25,
        format( 'the prefetch staged block %s, past the consistent block 25', ( SELECT max( block_num ) FROM hivemind_app._ops_staging_next ) );

    PERFORM hivemind_app.load_ops_staging_from_prefetch( 11, 20 );
    ASSERT NOT EXISTS ( SELECT * FROM hivemind_app._ops_staging EXCEPT ALL SELECT * FROM loaded )
       AND NOT EXISTS ( SELECT * FROM loaded EXCEPT ALL SELECT * FROM hivemind_app._ops_staging ),
        'the prefetched operations of 11..20 differ from what load_ops_staging(11, 20) stages';

    -- HAF hands out a shorter range than the one prefetched, as at a stage change
    PERFORM hivemind_app.load_ops_staging( 11, 15 );
    CREATE TEMP TABLE loaded_short AS SELECT * FROM hivemind_app._ops_staging;
    PERFORM hivemind_app.load_ops_staging_from_prefetch( 11, 15 );
    ASSERT ( SELECT count(*) FROM loaded_short ) = 15
       AND NOT EXISTS ( SELECT * FROM hivemind_app._ops_staging EXCEPT ALL SELECT * FROM loaded_short )
       AND NOT EXISTS ( SELECT * FROM loaded_short EXCEPT ALL SELECT * FROM hivemind_app._ops_staging ),
        'the prefetched operations of 11..15 differ from what load_ops_staging(11, 15) stages';

    -- the rename, with the handoff tables of pipelined massive sync
    BEGIN
        PERFORM hivemind_app.take_prefetched_ops_staging( 11, 20 );
        ASSERT FALSE, 'take_prefetched_ops_staging ran without the handoff tables';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM hivemind_app.set_stage_b_handoff( TRUE );
    FOREACH __range SLICE 1 IN ARRAY ARRAY[ [ 11, 20 ], [ 11, 15 ] ] LOOP
        PERFORM hivemind_app.load_ops_staging( __range[1], __range[2] );
        DROP TABLE IF EXISTS loaded_range;
        CREATE TEMP TABLE loaded_range AS SELECT * FROM hivemind_app._ops_staging;
        PERFORM hivemind_app.prefetch_ops_staging( 11, 40 );
        PERFORM hivemind_app.take_prefetched_ops_staging( __range[1], __range[2] );
        ASSERT ( SELECT array_agg( id ORDER BY ctid ) FROM hivemind_app._ops_staging )
             = ( SELECT array_agg( id ORDER BY id ) FROM loaded_range )
           AND NOT EXISTS ( SELECT * FROM hivemind_app._ops_staging EXCEPT ALL SELECT * FROM loaded_range )
           AND NOT EXISTS ( SELECT * FROM loaded_range EXCEPT ALL SELECT * FROM hivemind_app._ops_staging ),
            format( 'the operations take_prefetched_ops_staging(%s, %s) took differ from what load_ops_staging stages', __range[1], __range[2] );
        ASSERT ( SELECT count(*) FROM pg_index i WHERE i.indrelid = 'hivemind_app._ops_staging'::regclass ) = 2
           AND ( SELECT count(*) FROM pg_index i WHERE i.indrelid = 'hivemind_app._ops_staging_next'::regclass ) = 2
           AND to_regclass( 'hivemind_app._ops_staging_op_type_id_idx' ) IN
               ( SELECT i.indexrelid FROM pg_index i WHERE i.indrelid = 'hivemind_app._ops_staging'::regclass )
           AND to_regclass( 'hivemind_app._ops_staging_next_block_num_id_idx' ) IN
               ( SELECT i.indexrelid FROM pg_index i WHERE i.indrelid = 'hivemind_app._ops_staging_next'::regclass ),
            'take_prefetched_ops_staging left an index behind or under the other table''s name';
    END LOOP;

    __loaded_last := hivemind_app.prefetch_ops_staging( 26, 30 );
    ASSERT __loaded_last IS NULL, format( 'prefetch_ops_staging(26, 30) loaded up to block %s past the consistent block 25', __loaded_last );
    ASSERT NOT EXISTS ( SELECT 1 FROM hivemind_app._ops_staging_next ), 'a prefetch past the consistent block left rows staged';
END
$$;

ROLLBACK;
\echo ops prefetch: the next batch is staged as load_ops_staging stages it, up to the consistent block of HAF, copied or renamed
