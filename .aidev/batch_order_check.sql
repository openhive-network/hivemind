-- On the installed hivemind, checks inside one transaction that is rolled back that 12
-- blocks processed as one massive batch, as 3-block batches and one block at a time give
-- the same posts (ids included) and the same reply and follow notifications (ids
-- included), and that a replay of a batch whose follows phase committed gives them too:
--   - a post takes the id of the comment op creating it: ids follow operation order (a
--     reply before a root post of the same block takes the lower id) and an edit
--     takes an id it leaves unused;
--   - a notification is filtered by the mutes as they stood at the end of its block,
--     while bo-a mutes bo-b, unmutes, follows bo-c's muted list while bo-c mutes bo-b,
--     mutes bo-b again, resets the muted list and mutes bo-b once more, all inside the
--     12 blocks; the replay sees the lists as the batch left them (bo-b muted), not as
--     they were at block 2.
-- Seeds blocks, operations and accounts after HAF's last block (an empty HAF, as
-- .aidev/test-stack.compose.yml starts it, has none).
--   psql -X -v ON_ERROR_STOP=1 -f .aidev/batch_order_check.sql
\set QUIET on
BEGIN;
SET LOCAL statement_timeout = '300s';

SELECT hive.disable_fk_of_irreversible();

CREATE TEMP TABLE bo_base AS SELECT COALESCE(max(num), 0) AS b0 FROM hafd.blocks;
GRANT SELECT ON bo_base TO hivemind;

-- dated an hour ago, inside the 90-day notification window
INSERT INTO hafd.blocks
SELECT bo.b0 + b, ( '\xB0DD' || lpad( b::TEXT, 2, '0' ) )::bytea, '\xCAFE20',
       date_trunc( 'second', now() AT TIME ZONE 'UTC' ) - INTERVAL '1 hour' + b * INTERVAL '3 seconds',
       5, '\x4007', E'[]', '\x2157', 'STM65w', 1000, 1000, 1000000, 1000, 1000, 1000, 2000, 2000
FROM generate_series( 0, 12 ) AS b, bo_base bo
WHERE bo.b0 + b > 0
ON CONFLICT DO NOTHING;

-- a HAF hived has not started on yet has no operation types
INSERT INTO hafd.operation_types ( id, name, is_virtual ) VALUES
    ( 1, 'hive::protocol::comment_operation', FALSE ),
    ( 18, 'hive::protocol::custom_json_operation', FALSE )
ON CONFLICT DO NOTHING;
INSERT INTO hafd.custom_json_types ( custom_json_id ) VALUES ( 'follow' ) ON CONFLICT DO NOTHING;

-- (block, C: comment by author with permlink under parent | F: follow by author of
-- following with what), in operation order
CREATE TEMP TABLE bo_ops ( block INT, pos INT, kind CHAR, author TEXT, permlink TEXT, parent TEXT, what TEXT );
INSERT INTO bo_ops VALUES
    ( 1, 0, 'C', 'bo-a', 'root', NULL, NULL ),
    ( 1, 1, 'C', 'bo-c', 'c1', NULL, NULL ),
    ( 2, 0, 'F', 'bo-b', 'bo-a', NULL, 'blog' ),
    ( 3, 0, 'F', 'bo-a', 'bo-b', NULL, 'ignore' ),
    ( 3, 1, 'F', 'bo-b', 'bo-a', NULL, 'blog' ),
    ( 3, 2, 'C', 'bo-b', 'r3', 'bo-a/root', NULL ),
    ( 4, 0, 'F', 'bo-a', 'bo-b', NULL, '' ),
    ( 4, 1, 'C', 'bo-a', 'root', NULL, NULL ),          -- an edit
    ( 5, 0, 'F', 'bo-b', 'bo-a', NULL, 'blog' ),
    ( 5, 1, 'C', 'bo-b', 'r5', 'bo-a/root', NULL ),
    ( 6, 0, 'C', 'bo-b', 'r6', 'bo-a/root', NULL ),     -- a reply before a root post
    ( 6, 1, 'C', 'bo-c', 'c2', NULL, NULL ),
    ( 6, 2, 'F', 'bo-a', 'bo-c', NULL, 'follow_muted' ),
    ( 6, 3, 'F', 'bo-c', 'bo-b', NULL, 'ignore' ),
    ( 7, 0, 'F', 'bo-b', 'bo-a', NULL, 'blog' ),
    ( 7, 1, 'C', 'bo-b', 'r7', 'bo-a/root', NULL ),
    ( 8, 0, 'F', 'bo-c', 'bo-b', NULL, '' ),
    ( 9, 0, 'F', 'bo-b', 'bo-a', NULL, 'blog' ),
    ( 9, 1, 'C', 'bo-b', 'r9', 'bo-a/root', NULL ),
    ( 10, 0, 'F', 'bo-a', 'bo-b', NULL, 'ignore' ),
    ( 10, 1, 'F', 'bo-b', 'bo-a', NULL, 'blog' ),
    ( 10, 2, 'C', 'bo-b', 'r10', 'bo-a/root', NULL ),
    ( 11, 0, 'F', 'bo-a', 'bo-b', NULL, 'reset_muted_list' ),
    ( 12, 0, 'F', 'bo-b', 'bo-a', NULL, 'blog' ),
    ( 12, 1, 'C', 'bo-b', 'r12', 'bo-a/root', NULL ),
    ( 12, 2, 'F', 'bo-a', 'bo-b', NULL, 'ignore' );

INSERT INTO hafd.operations ( id, trx_in_block, op_type_id, op_pos, body_value, custom_json_type_id )
SELECT hafd.operation_id( bo.b0 + o.block, o.pos ), o.pos, CASE o.kind WHEN 'C' THEN 1 ELSE 18 END, o.pos,
       CASE o.kind
           WHEN 'C' THEN jsonb_build_object( 'author', o.author, 'permlink', o.permlink,
               'parent_author', COALESCE( split_part( o.parent, '/', 1 ), '' ),
               'parent_permlink', COALESCE( split_part( o.parent, '/', 2 ), 'bo-cat' ),
               'title', '', 'body', 'body', 'json_metadata', '{}' )
           ELSE jsonb_build_object( 'id', 'follow', 'required_auths', '[]'::jsonb,
               'required_posting_auths', jsonb_build_array( o.author ),
               'json', jsonb_build_array( 'follow', jsonb_build_object( 'follower', o.author, 'following', o.permlink,
                   'what', CASE WHEN o.what = '' THEN '[]'::jsonb ELSE jsonb_build_array( o.what ) END ) )::TEXT )
       END,
       CASE o.kind WHEN 'F' THEN ( SELECT id FROM hafd.custom_json_types WHERE custom_json_id = 'follow' ) END
FROM bo_ops o, bo_base bo;

UPDATE hafd.contexts SET current_block_num = ( SELECT b0 + 12 FROM bo_base ), irreversible_block = ( SELECT b0 + 12 FROM bo_base )
WHERE name = 'hivemind_app';

SET LOCAL ROLE hivemind;

INSERT INTO hivemind_app.hive_accounts (id, name, created_at)
SELECT (SELECT max(id) FROM hivemind_app.hive_accounts) + a.n, a.name, '2016-06-01'
FROM unnest(ARRAY['bo-a', 'bo-b', 'bo-c']) WITH ORDINALITY AS a(name, n);

-- Processes the 12 blocks in batches of _size as massive sync's phases do, with
-- _replay_follows a follows phase run again over its own committed result; returns the
-- posts and notifications, accounts and posts by name.
CREATE FUNCTION pg_temp.bo_run( _size INT, _replay_follows BOOLEAN ) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE
    _b0 INT := ( SELECT b0 FROM bo_base );
    _first INT;
    _last INT;
BEGIN
    FOR _first IN _b0 + 1 .. _b0 + 12 BY _size LOOP
        _last := LEAST( _first + _size - 1, _b0 + 12 );
        DELETE FROM hivemind_app._batch_queue;
        INSERT INTO hivemind_app._batch_queue ( first_block, last_block ) VALUES ( _first, _last );
        PERFORM hivemind_app.load_ops_staging( _first, _last );
        PERFORM count(*) FROM hivemind_app.process_posts_from_staging( 2147483647 );
        -- each phase is its own transaction in a sync, which drops its temporary tables
        DROP TABLE IF EXISTS pg_temp._follow_notifications;
        PERFORM count(*) FROM hivemind_app.process_follows_for_blocks( _first, _last );
        IF _replay_follows THEN
            DROP TABLE IF EXISTS pg_temp._follow_notifications;
            DELETE FROM hivemind_app._follow_notification_events;
            PERFORM count(*) FROM hivemind_app.process_follows_for_blocks( _first, _last );
        END IF;
        PERFORM hivemind_app.flush_post_notifications_for_blocks( _first, _last );
        PERFORM hivemind_app.flush_follow_notifications_for_blocks( _first, _last );
        DELETE FROM hivemind_app._batch_queue;
    END LOOP;
    RETURN jsonb_build_object(
        'posts', ( SELECT jsonb_agg( jsonb_build_array( hp.id, ha.name || '/' || hpd.permlink, hp.block_num_created ) ORDER BY hp.id )
                   FROM hivemind_app.hive_posts hp
                   JOIN hivemind_app.hive_accounts ha ON ha.id = hp.author_id
                   JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
                   WHERE ha.name LIKE 'bo-_' ),
        'notifications', ( SELECT jsonb_agg( jsonb_build_object( 'id', n.id, 'type_id', n.type_id, 'block', n.block_num - _b0,
                               'src', s.name, 'dst', d.name, 'post', hpd.permlink ) ORDER BY n.id )
                           FROM hivemind_app.hive_notification_cache n
                           JOIN hivemind_app.hive_accounts s ON s.id = n.src
                           JOIN hivemind_app.hive_accounts d ON d.id = n.dst
                           LEFT JOIN hivemind_app.hive_posts hp ON hp.id = n.post_id
                           LEFT JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
                           WHERE s.name LIKE 'bo-_' ) );
END
$$;

-- Each mode but the last runs in a subtransaction its own exception rolls back; its
-- result survives in a PL/pgSQL variable (a row written there would be rolled back too).
DO $$
DECLARE
    __modes TEXT[] := ARRAY['one batch', '3-block batches', 'one batch, follows replayed'];
    __sizes INT[] := ARRAY[12, 3, 12];
    __results JSONB[] := '{}';
    __blocks JSONB;
    __post_order TEXT;
    __notified TEXT;
BEGIN
    FOR __i IN 1 .. cardinality( __modes ) LOOP
        BEGIN
            __results := __results || pg_temp.bo_run( __sizes[__i], __modes[__i] LIKE '%replayed' );
            RAISE SQLSTATE 'BORUN';
        EXCEPTION WHEN SQLSTATE 'BORUN' THEN NULL;
        END;
    END LOOP;
    __blocks := pg_temp.bo_run( 1, FALSE );

    FOR __i IN 1 .. cardinality( __modes ) LOOP
        ASSERT __results[__i] IS NOT DISTINCT FROM __blocks,
            format( E'%s differs from one block at a time:\n%s\n%s', __modes[__i], __results[__i], __blocks );
    END LOOP;

    SELECT string_agg( p->>1, ' ' ORDER BY ( p->>0 )::INT ) INTO __post_order FROM jsonb_array_elements( __blocks->'posts' ) p;
    ASSERT __post_order = 'bo-a/root bo-c/c1 bo-b/r3 bo-b/r5 bo-b/r6 bo-c/c2 bo-b/r7 bo-b/r9 bo-b/r10 bo-b/r12',
        format( 'post ids are not in operation order: %s', __post_order );
    ASSERT ( SELECT ( p->>0 )::INT FROM jsonb_array_elements( __blocks->'posts' ) p WHERE p->>1 = 'bo-b/r5' )
         = ( SELECT ( p->>0 )::INT FROM jsonb_array_elements( __blocks->'posts' ) p WHERE p->>1 = 'bo-b/r3' ) + 2,
        format( 'the edit of bo-a/root between bo-b/r3 and bo-b/r5 should leave its id unused: %s', __blocks->'posts' );

    SELECT string_agg( format( '%s@%s', n->>'type_id', n->>'block' ), ' ' ORDER BY ( n->>'block' )::INT, n->>'type_id' )
    INTO __notified FROM jsonb_array_elements( __blocks->'notifications' ) n;
    ASSERT __notified = '15@2 12@5 15@5 12@9 15@9',
        format( 'expected reply (12) and follow (15) notifications in the blocks bo-a did not mute bo-b, got %s', __notified );
END
$$;

ROLLBACK;
\echo batch order: 12 blocks as one batch, 3-block batches and one block at a time give the same post ids and notifications
