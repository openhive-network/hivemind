-- Pipelined massive sync runs Stage B of a batch (reblogs, post counts, notifications, ...)
-- after Stage A of the next batch (posts) has committed. Checks, in a transaction rolled
-- back, that two batches leave the same posts, reblogs (and the hive_reblogs ids drawn),
-- reblog notifications and post_count whether each batch's Stage B runs right after its
-- own Stage A (Stage B reading views of Stage A's tables, as live sync and the default
-- massive sync run it), after the next batch's Stage A (the pipelined order, Stage B
-- reading the tables hand_off_to_stage_b fills), or one block at a time:
--   - the first batch reblogs a post the second batch deletes and re-creates, and one it
--     deletes: both reblogs are inserted, notified and then removed by the second
--     batch's delete cascade, which runs in its Stage B;
--   - the first batch reblogs a post the second batch creates: there is no post to reblog;
--   - the second batch reblogs the re-created post.
-- Seeds its own accounts and staged operations at block numbers past any chain, inside
-- the notification window; runs on any installed hivemind schema:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/pipelined_stage_order.sql

\set ON_ERROR_STOP 1
BEGIN;

INSERT INTO hivemind_app.hive_accounts (id, name, created_at)
SELECT (SELECT max(id) FROM hivemind_app.hive_accounts) + a.n, a.name, '2016-06-01'
FROM unnest(ARRAY['ps-a', 'ps-r1', 'ps-r2']) WITH ORDINALITY AS a(name, n);

-- (block, position, C: comment by ps-a | D: its delete | R: reblog by account, permlink);
-- blocks are offsets from 2,000,000,000
CREATE TEMP TABLE ps_ops (block INT, pos INT, op CHAR, account TEXT, permlink TEXT);
INSERT INTO ps_ops VALUES
  (300, 0, 'C', NULL, 'ps-p'), (300, 1, 'C', NULL, 'ps-q'),
  (302, 0, 'R', 'ps-r1', 'ps-p'), (302, 1, 'R', 'ps-r1', 'ps-s'),
  (303, 0, 'R', 'ps-r2', 'ps-q'),
  (304, 0, 'D', NULL, 'ps-p'), (304, 1, 'D', NULL, 'ps-q'),
  (305, 0, 'C', NULL, 'ps-p'), (305, 1, 'C', NULL, 'ps-s'),
  (306, 0, 'R', 'ps-r2', 'ps-p');

CREATE FUNCTION pg_temp.ps_stage_a(_first INT, _last INT) RETURNS VOID AS $$
BEGIN
    DELETE FROM hivemind_app._ops_staging;
    INSERT INTO hivemind_app._ops_staging (id, block_num, block_date, op_type_id, val)
    SELECT (2000000000 + o.block)::BIGINT * 10 + o.pos, 2000000000 + o.block,
      '2016-06-03'::TIMESTAMP + o.block * INTERVAL '3 seconds',
      CASE o.op WHEN 'C' THEN 1 WHEN 'D' THEN 17 ELSE 18 END,
      CASE o.op
        WHEN 'C' THEN jsonb_build_object('author', 'ps-a', 'permlink', o.permlink, 'parent_author', '',
          'parent_permlink', 'ps-cat', 'title', '', 'body', 'body of ' || o.permlink, 'json_metadata', '{}')
        WHEN 'D' THEN jsonb_build_object('author', 'ps-a', 'permlink', o.permlink)
        ELSE jsonb_build_object('id', 'reblog', 'required_auths', '[]'::jsonb,
          'required_posting_auths', jsonb_build_array(o.account),
          'json', jsonb_build_array('reblog', jsonb_build_object('account', o.account, 'author', 'ps-a',
            'permlink', o.permlink))::TEXT)
      END
    FROM ps_ops o
    WHERE 2000000000 + o.block BETWEEN _first AND _last;
    PERFORM count(*) FROM hivemind_app.process_posts_from_staging(2147483647);
END
$$ LANGUAGE plpgsql;

CREATE FUNCTION pg_temp.ps_stage_b(_first INT, _last INT) RETURNS VOID AS $$
BEGIN
    PERFORM hivemind_app.process_reblogs_from_staging(_last);
    PERFORM hivemind_app.process_post_counts_from_staging(_first);
    PERFORM hivemind_app.flush_reblog_notifications_for_blocks(_first, _last);
END
$$ LANGUAGE plpgsql;

-- The posts, reblogs (ids as offsets past _reblog_id), reblog notifications and post_count
CREATE FUNCTION pg_temp.ps_state(_reblog_id BIGINT) RETURNS JSONB AS $$
    SELECT jsonb_build_object(
      'posts', (SELECT jsonb_agg(jsonb_build_array(hp.id, hpd.permlink, hp.counter_deleted,
                  hp.block_num_created - 2000000000, hp.block_num - 2000000000) ORDER BY hp.id)
                FROM hivemind_app.hive_posts hp
                JOIN hivemind_app.hive_accounts ha ON ha.id = hp.author_id
                JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
                WHERE ha.name = 'ps-a'),
      'reblogs', (SELECT jsonb_agg(jsonb_build_array(hr.id - _reblog_id, ha.name, hpd.permlink, hp.counter_deleted,
                    hr.block_num - 2000000000) ORDER BY hr.id)
                  FROM hivemind_app.hive_reblogs hr
                  JOIN hivemind_app.hive_accounts ha ON ha.id = hr.blogger_id
                  JOIN hivemind_app.hive_posts hp ON hp.id = hr.post_id
                  JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
                  WHERE ha.name LIKE 'ps-r_'),
      'reblog_ids_drawn', COALESCE(pg_sequence_last_value(pg_get_serial_sequence('hivemind_app.hive_reblogs', 'id')::regclass), 0)
                          - _reblog_id,
      'notifications', (SELECT jsonb_agg(jsonb_build_array(n.id, n.type_id, n.block_num - 2000000000, s.name, hpd.permlink,
                          hp.counter_deleted) ORDER BY n.id)
                        FROM hivemind_app.hive_notification_cache n
                        JOIN hivemind_app.hive_accounts s ON s.id = n.src
                        LEFT JOIN hivemind_app.hive_posts hp ON hp.id = n.post_id
                        LEFT JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
                        WHERE s.name LIKE 'ps-%'),
      'post_count', (SELECT ha.post_count FROM hivemind_app.hive_accounts ha WHERE ha.name = 'ps-a'));
$$ LANGUAGE sql;

CREATE FUNCTION pg_temp.ps_reblog_id() RETURNS BIGINT AS $$
    SELECT COALESCE(pg_sequence_last_value(pg_get_serial_sequence('hivemind_app.hive_reblogs', 'id')::regclass), 0);
$$ LANGUAGE sql;

-- Batches of _size blocks, each batch's Stage B right after its Stage A
CREATE FUNCTION pg_temp.ps_sequential(_size INT) RETURNS JSONB AS $$
DECLARE
    _reblog_id BIGINT := pg_temp.ps_reblog_id();
BEGIN
    PERFORM hivemind_app.set_stage_b_handoff(FALSE);
    FOR _first IN 2000000300 .. 2000000306 BY _size LOOP
        PERFORM pg_temp.ps_stage_a(_first, LEAST(_first + _size - 1, 2000000306));
        PERFORM pg_temp.ps_stage_b(_first, LEAST(_first + _size - 1, 2000000306));
    END LOOP;
    RETURN pg_temp.ps_state(_reblog_id);
END
$$ LANGUAGE plpgsql;

-- Blocks 300-303 and 304-306, the first batch's Stage B after the second batch's Stage A
CREATE FUNCTION pg_temp.ps_pipelined() RETURNS JSONB AS $$
DECLARE
    _reblog_id BIGINT := pg_temp.ps_reblog_id();
BEGIN
    PERFORM hivemind_app.set_stage_b_handoff(TRUE);
    PERFORM pg_temp.ps_stage_a(2000000300, 2000000303);
    PERFORM hivemind_app.hand_off_to_stage_b();
    PERFORM pg_temp.ps_stage_a(2000000304, 2000000306);
    PERFORM pg_temp.ps_stage_b(2000000300, 2000000303);
    PERFORM hivemind_app.hand_off_to_stage_b();
    PERFORM pg_temp.ps_stage_b(2000000304, 2000000306);
    RETURN pg_temp.ps_state(_reblog_id);
END
$$ LANGUAGE plpgsql;

SAVEPOINT runs;
SELECT pg_temp.ps_sequential(4) AS sequential_state \gset
ROLLBACK TO SAVEPOINT runs;
SELECT pg_temp.ps_pipelined() AS pipelined_state \gset
ROLLBACK TO SAVEPOINT runs;
SELECT pg_temp.ps_sequential(1) AS block_state \gset

CREATE FUNCTION pg_temp.ps_check(_sequential JSONB, _pipelined JSONB, _blocks JSONB) RETURNS VOID AS $$
BEGIN
    IF _sequential IS DISTINCT FROM _blocks THEN
        RAISE EXCEPTION E'sequential batches differ from blocks processed one at a time:\nbatches: %\nblocks:  %', _sequential, _blocks;
    END IF;
    IF _pipelined IS DISTINCT FROM _blocks THEN
        RAISE EXCEPTION E'pipelined batches differ from blocks processed one at a time:\npipelined: %\nblocks:    %', _pipelined, _blocks;
    END IF;
    IF _blocks->'reblogs' IS DISTINCT FROM '[[3, "ps-r2", "ps-p", 0, 306]]'::JSONB
       OR (_blocks->>'reblog_ids_drawn')::INT <> 3 THEN
        RAISE EXCEPTION 'expected the reblogs of 302 and 303 inserted and then removed by the deletes at 304, and the reblog at 306 kept, got % (% ids drawn)',
            _blocks->'reblogs', _blocks->'reblog_ids_drawn';
    END IF;
    IF (SELECT array_agg(n->>2 || ':' || (n->>3) || ':' || (n->>4) || '#' || (n->>5) ORDER BY n->>2, n->>3)
        FROM jsonb_array_elements(_blocks->'notifications') n WHERE (n->>1)::INT = 14)
       IS DISTINCT FROM ARRAY['302:ps-r1:ps-p#1', '303:ps-r2:ps-q#1', '306:ps-r2:ps-p#0'] THEN
        RAISE EXCEPTION 'expected reblog notifications at 302, 303 (on the versions deleted at 304) and 306, got %', _blocks->'notifications';
    END IF;
    IF (_blocks->>'post_count')::INT <> 2 THEN
        RAISE EXCEPTION 'expected post_count 2 (ps-p re-created, ps-s), got %', _blocks->'post_count';
    END IF;
END
$$ LANGUAGE plpgsql;

SELECT pg_temp.ps_check(:'sequential_state'::JSONB, :'pipelined_state'::JSONB, :'block_state'::JSONB);

ROLLBACK;
