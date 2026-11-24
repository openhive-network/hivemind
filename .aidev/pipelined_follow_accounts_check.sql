-- On the installed hivemind, checks inside one transaction that is rolled back that two
-- massive batches leave the same follows, mutes, follow counters and follow notifications
-- whether each batch's Stage B runs right after its own Stage A (sequential) or after the
-- next batch's Stage A (pipelined), where Stage B of the first batch finds the accounts
-- the second batch's Stage A registered:
--   - in the first batch (blocks 1-3) pf-a follows pf-t and mutes pf-m, accounts created
--     in the second batch (blocks 4, 5): both actions are dropped, as accounts that do not
--     exist yet, and pf-a's follow notification of pf-t is not built;
--   - in the second batch pf-a follows pf-n at block 4, created at block 5 of the same
--     batch: kept, as a batch resolves names as of its last block.
-- The ops start at block 2: a notification takes the date of the block before its own.
-- Seeds blocks, operations and HAF accounts after HAF's last block and account (an empty
-- HAF, as .aidev/test-stack.compose.yml starts it, has none).
--   psql -X -v ON_ERROR_STOP=1 -f .aidev/pipelined_follow_accounts_check.sql
\set QUIET on
BEGIN;
SET LOCAL statement_timeout = '300s';

SELECT hive.disable_fk_of_irreversible();

CREATE TEMP TABLE pf_base AS
SELECT COALESCE(max(num), 0) AS b0,
       GREATEST((SELECT max(id) FROM hafd.accounts), (SELECT max(id) FROM hivemind_app.hive_accounts)) + 1 AS a0
FROM hafd.blocks;
GRANT SELECT ON pf_base TO hivemind;

-- dated an hour ago, inside the 90-day notification window
INSERT INTO hafd.blocks
SELECT pf.b0 + b, ( '\xBFDD' || lpad( b::TEXT, 2, '0' ) )::bytea, '\xCAFE20',
       date_trunc( 'second', now() AT TIME ZONE 'UTC' ) - INTERVAL '1 hour' + b * INTERVAL '3 seconds',
       5, '\x4007', E'[]', '\x2157', 'STM65w', 1000, 1000, 1000000, 1000, 1000, 1000, 2000, 2000
FROM generate_series( 0, 5 ) AS b, pf_base pf
WHERE pf.b0 + b > 0
ON CONFLICT DO NOTHING;

-- a HAF hived has not started on yet has no operation types
INSERT INTO hafd.operation_types ( id, name, is_virtual ) VALUES
    ( 9, 'hive::protocol::account_create_operation', FALSE ),
    ( 18, 'hive::protocol::custom_json_operation', FALSE )
ON CONFLICT DO NOTHING;
INSERT INTO hafd.custom_json_types ( custom_json_id ) VALUES ( 'follow' ) ON CONFLICT DO NOTHING;

-- (block, position, A: account_create of account | F: follow by pf-a of account with what)
CREATE TEMP TABLE pf_ops ( block INT, pos INT, kind CHAR, account TEXT, what TEXT );
INSERT INTO pf_ops VALUES
    ( 2, 0, 'F', 'pf-t', 'blog' ),
    ( 3, 0, 'F', 'pf-m', 'ignore' ),
    ( 4, 0, 'A', 'pf-t', NULL ),
    ( 4, 1, 'F', 'pf-n', 'blog' ),
    ( 5, 0, 'A', 'pf-m', NULL ),
    ( 5, 1, 'A', 'pf-n', NULL );

INSERT INTO hafd.accounts ( id, name, block_num )
SELECT pf.a0 + o.pos * 10 + o.block, o.account, pf.b0 + o.block FROM pf_ops o, pf_base pf WHERE o.kind = 'A';

INSERT INTO hafd.operations ( id, trx_in_block, op_type_id, op_pos, body_value, custom_json_type_id )
SELECT hafd.operation_id( pf.b0 + o.block, o.pos ), o.pos, CASE o.kind WHEN 'A' THEN 9 ELSE 18 END, o.pos,
       CASE o.kind
           WHEN 'A' THEN jsonb_build_object( 'new_account_name', o.account, 'json_metadata', '', 'posting_json_metadata', '' )
           ELSE jsonb_build_object( 'id', 'follow', 'required_auths', '[]'::jsonb,
               'required_posting_auths', jsonb_build_array( 'pf-a' ),
               'json', jsonb_build_array( 'follow', jsonb_build_object( 'follower', 'pf-a', 'following', o.account,
                   'what', jsonb_build_array( o.what ) ) )::TEXT )
       END,
       CASE o.kind WHEN 'F' THEN ( SELECT id FROM hafd.custom_json_types WHERE custom_json_id = 'follow' ) END
FROM pf_ops o, pf_base pf;

UPDATE hafd.contexts SET current_block_num = ( SELECT b0 + 5 FROM pf_base ), irreversible_block = ( SELECT b0 + 5 FROM pf_base )
WHERE name = 'hivemind_app';

SET LOCAL ROLE hivemind;

INSERT INTO hivemind_app.hive_accounts ( id, name, created_at )
SELECT pf.a0 + 100, 'pf-a', '2016-06-01' FROM pf_base pf;

CREATE FUNCTION pg_temp.pf_stage_a( _first INT, _last INT ) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO hivemind_app._batch_queue ( first_block, last_block ) VALUES ( _first, _last );
    PERFORM hivemind_app.load_ops_staging( _first, _last );
    PERFORM hivemind_app.process_accounts_from_staging( 0 );
END
$$;

CREATE FUNCTION pg_temp.pf_stage_b( _first INT, _last INT ) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    -- each phase is its own transaction in a sync, which drops its temporary tables
    DROP TABLE IF EXISTS pg_temp._follow_notifications;
    PERFORM count(*) FROM hivemind_app.process_follows_for_blocks( _first, _last );
    PERFORM hivemind_app.flush_follow_notifications_for_blocks( _first, _last );
    DELETE FROM hivemind_app._batch_queue WHERE first_block = _first;
END
$$;

-- Runs blocks 1-3 and 4-5 as two batches, pipelined or not; returns pf-a's follows and
-- mutes, the follow counters and the follow notifications, accounts by name.
CREATE FUNCTION pg_temp.pf_run( _pipelined BOOLEAN ) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE
    _b0 INT := ( SELECT b0 FROM pf_base );
BEGIN
    DELETE FROM hivemind_app._batch_queue;
    PERFORM hivemind_app.set_stage_b_handoff( _pipelined );
    IF _pipelined THEN
        PERFORM pg_temp.pf_stage_a( _b0 + 1, _b0 + 3 );
        PERFORM hivemind_app.hand_off_to_stage_b();
        PERFORM pg_temp.pf_stage_a( _b0 + 4, _b0 + 5 );
        PERFORM pg_temp.pf_stage_b( _b0 + 1, _b0 + 3 );
        PERFORM hivemind_app.hand_off_to_stage_b();
        PERFORM pg_temp.pf_stage_b( _b0 + 4, _b0 + 5 );
    ELSE
        PERFORM pg_temp.pf_stage_a( _b0 + 1, _b0 + 3 );
        PERFORM pg_temp.pf_stage_b( _b0 + 1, _b0 + 3 );
        PERFORM pg_temp.pf_stage_a( _b0 + 4, _b0 + 5 );
        PERFORM pg_temp.pf_stage_b( _b0 + 4, _b0 + 5 );
    END IF;
    RETURN jsonb_build_object(
        'follows', ( SELECT jsonb_agg( format( '%s>%s@%s', fr.name, fo.name, f.block_num - _b0 ) ORDER BY fo.name )
                     FROM hivemind_app.follows f
                     JOIN hivemind_app.hive_accounts fr ON fr.id = f.follower
                     JOIN hivemind_app.hive_accounts fo ON fo.id = f.following
                     WHERE fr.name = 'pf-a' ),
        'muted', ( SELECT jsonb_agg( fo.name ORDER BY fo.name )
                   FROM hivemind_app.muted m
                   JOIN hivemind_app.hive_accounts fr ON fr.id = m.follower
                   JOIN hivemind_app.hive_accounts fo ON fo.id = m.following
                   WHERE fr.name = 'pf-a' ),
        'counters', ( SELECT jsonb_object_agg( ha.name, format( '%s/%s', ha.followers, ha.following ) )
                      FROM hivemind_app.hive_accounts ha WHERE ha.name LIKE 'pf-_' ),
        'notifications', ( SELECT jsonb_agg( format( '%s>%s@%s', s.name, d.name, n.block_num - _b0 ) ORDER BY n.id )
                           FROM hivemind_app.hive_notification_cache n
                           JOIN hivemind_app.hive_accounts s ON s.id = n.src
                           JOIN hivemind_app.hive_accounts d ON d.id = n.dst
                           WHERE n.type_id = 15 AND s.name = 'pf-a' ) );
END
$$;

-- The sequential run is in a subtransaction its own exception rolls back; its result
-- survives in a PL/pgSQL variable.
DO $$
DECLARE
    __sequential JSONB;
    __pipelined JSONB;
    __expected JSONB := jsonb_build_object(
        'follows', '["pf-a>pf-n@4"]'::JSONB,
        'muted', NULL,
        'counters', '{"pf-a": "0/1", "pf-m": "0/0", "pf-n": "1/0", "pf-t": "0/0"}'::JSONB,
        'notifications', '["pf-a>pf-n@4"]'::JSONB );
BEGIN
    IF ( SELECT count(*) FROM hivemind_app.accounts_view av WHERE av.name IN ( 'pf-t', 'pf-m', 'pf-n' ) ) <> 3 THEN
        RAISE EXCEPTION 'setup: hivemind_app.accounts_view does not show the 3 seeded HAF accounts';
    END IF;

    BEGIN
        __sequential := pg_temp.pf_run( FALSE );
        RAISE SQLSTATE 'PFRUN';
    EXCEPTION WHEN SQLSTATE 'PFRUN' THEN NULL;
    END;
    __pipelined := pg_temp.pf_run( TRUE );

    IF __sequential IS DISTINCT FROM __expected THEN
        RAISE EXCEPTION E'sequential batches: expected the follow of pf-n only (pf-t and pf-m do not exist in the first batch)\nexpected: %\ngot:      %',
            __expected, __sequential;
    END IF;
    IF __pipelined IS DISTINCT FROM __sequential THEN
        RAISE EXCEPTION E'pipelined batches differ from sequential ones (Stage B saw accounts of the next batch):\npipelined:  %\nsequential: %',
            __pipelined, __sequential;
    END IF;
END
$$;

ROLLBACK;
\echo pipelined follow accounts: a follow and a mute of accounts the next batch creates are dropped in both modes
