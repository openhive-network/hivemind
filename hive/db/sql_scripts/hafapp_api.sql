DROP TYPE IF EXISTS hivemind_app.hive_api_operation CASCADE;
CREATE TYPE hivemind_app.hive_api_operation AS (
    id BIGINT,
    block_num INT,
    operation_type_id INTEGER,
    is_virtual BOOLEAN,
    body VARCHAR
);

DROP TYPE IF EXISTS hivemind_app.hive_api_operation_in_block CASCADE;
CREATE TYPE hivemind_app.hive_api_operation_in_block AS (
      block_num INT
    , operations jsonb[] -- hivemind_app.hive_api_operation
);


CREATE OR REPLACE FUNCTION hivemind_app.enum_operations4hivemind(in _first_block INT, in _last_block INT)
    RETURNS SETOF hivemind_app.hive_api_operation_in_block
AS
$function$
BEGIN
    /** Hivemind requires only following kinds of virtual operations:
    author_reward_operation                 = 51
    comment_reward_operation                = 53
    effective_comment_vote_operation        = 72
    comment_payout_update_operation         = 61
    ineffective_delete_comment_operation    = 73
    */


    RETURN QUERY -- enum_operations4hivemind
        SELECT
            op.block_num
             , ARRAY_AGG( to_jsonb(op.*) ORDER BY op.id )
        FROM
            (SELECT
                    ho.id
                  , ho.block_num
                  , ho.op_type_id as operation_type_id
                  , ho.op_type_id >= 50 AS is_virtual
                  , ho.body::VARCHAR
             FROM hivemind_app.operations_view ho
             WHERE ho.block_num BETWEEN _first_block AND _last_block
               AND (ho.op_type_id < 50
                 OR ho.op_type_id in (51, 53, 61, 72, 73)
                 )
               AND (ho.op_type_id != 18
                 OR ho.custom_json_type_id IN (
                     SELECT id FROM hafd.custom_json_types
                     WHERE custom_json_id IN ('follow', 'reblog', 'community', 'notify')
                 ))
            ) as op
        GROUP BY op.block_num
    ;
END;
$function$
    LANGUAGE plpgsql STABLE
;

DROP TYPE IF EXISTS hivemind_app.hive_api_hivemind_blocks CASCADE;
CREATE TYPE hivemind_app.hive_api_hivemind_blocks AS (
    num INTEGER,
    hash BYTEA,
    prev BYTEA,
    date TEXT,
    operations jsonb[]
);


CREATE OR REPLACE FUNCTION hivemind_app.enum_blocks4hivemind(in _first_block INT, in _last_block INT)
    RETURNS SETOF hivemind_app.hive_api_hivemind_blocks
AS
$function$
BEGIN
    RETURN QUERY
        SELECT -- hivemind_app.hive_api_hivemind_blocks
               hb.num
             , hb.hash
             , hb.prev as prev
             , to_char( created_at,  'YYYY-MM-DDThh24:MI:SS' ) as date
             , COALESCE( oper.operations, '{}'::jsonb[] ) as operations
        FROM hivemind_app.blocks_view hb
                 LEFT JOIN (
            SELECT
                   op.block_num
                 , ARRAY_AGG( to_jsonb(op) ORDER BY op.id ) as operations
            FROM
                (SELECT
                     ho.id
                      , ho.block_num
                      , ho.op_type_id as operation_type_id
                      , ho.op_type_id >= 50 AS is_virtual
                      , ho.body::VARCHAR
                 FROM hivemind_app.operations_view ho
                 WHERE ho.block_num BETWEEN _first_block AND _last_block
                   AND (ho.op_type_id < 50
                     OR ho.op_type_id in (51, 53, 61, 72, 73)
                     )
                   AND (ho.op_type_id != 18
                     OR ho.custom_json_type_id IN (
                         SELECT id FROM hafd.custom_json_types
                         WHERE custom_json_id IN ('follow', 'reblog', 'community', 'notify')
                     ))
                ) as op
            GROUP BY op.block_num
        ) as oper ON oper.block_num = hb.num
        WHERE hb.num BETWEEN _first_block AND _last_block
        ORDER by hb.num
    ;
END
$function$
    LANGUAGE plpgsql STABLE
;

--- Flat-row functions for massive sync (no ARRAY_AGG, no type wrapper, no hash/prev) ---

DROP TYPE IF EXISTS hivemind_app.hivemind_flat_op CASCADE;
CREATE TYPE hivemind_app.hivemind_flat_op AS (
    block_num INT,
    op_type_id INT,
    body JSONB
);

CREATE OR REPLACE FUNCTION hivemind_app.get_ops_for_hivemind(in _first_block INT, in _last_block INT)
    RETURNS SETOF hivemind_app.hivemind_flat_op
AS
$function$
BEGIN
    /** Flat-row query for massive sync - returns only the op types hivemind processes.
        Regular ops:  0=vote, 1=comment, 9=account_create, 10=account_update,
                      14=pow, 17=delete_comment, 18=custom_json, 19=comment_option,
                      23=create_claimed_account, 30=pow2, 41=account_create_with_delegation,
                      43=account_update2
        Virtual ops:  51=author_reward, 53=comment_reward, 61=comment_payout_update,
                      72=effective_comment_vote, 73=ineffective_delete_comment

        Body is returned as jsonb->'value' (the inner payload, no type wrapper).
    */
    RETURN QUERY
        SELECT
            ho.block_num,
            ho.op_type_id,
            ho.body->'value'
        FROM hivemind_app.operations_view ho
        WHERE ho.block_num BETWEEN _first_block AND _last_block
          AND ho.op_type_id IN (0,1,9,10,14,17,18,19,23,30,41,43, 51,53,61,72,73)
          AND (ho.op_type_id != 18
            OR ho.custom_json_type_id IN (
                SELECT id FROM hafd.custom_json_types
                WHERE custom_json_id IN ('follow', 'reblog', 'community', 'notify')
            ))
        ORDER BY ho.id
    ;
END
$function$
    LANGUAGE plpgsql STABLE
;

--- Process follow operations entirely in SQL for massive sync ---

DROP TYPE IF EXISTS hivemind_app.follow_notification CASCADE;
CREATE TYPE hivemind_app.follow_notification AS (
    follower_name TEXT,
    following_name TEXT,
    block_num INT
);

CREATE OR REPLACE FUNCTION hivemind_app.process_follows_for_blocks(
    _first_block INT, _last_block INT
) RETURNS SETOF hivemind_app.follow_notification
AS $function$
DECLARE
    rec RECORD;
    _val JSONB;
    _inner_json JSONB;
    _data JSONB;
    _auth_account TEXT;
    _follower_name TEXT;
    _following_raw JSONB;
    _what_action TEXT;
    _follower_id INT;
    _following_name TEXT;
    _following_id INT;
    _following_arr TEXT[];
    _i INT;
    _op_seq BIGINT := 0;
BEGIN
    CREATE TEMP TABLE IF NOT EXISTS _follow_notifications (
        follower_name TEXT,
        following_name TEXT,
        block_num INT
    ) ON COMMIT DROP;

    -- Temp table for collecting parsed follow actions (Phase 1 output)
    CREATE TEMP TABLE IF NOT EXISTS _follow_actions (
        follower_name TEXT NOT NULL,
        following_name TEXT NOT NULL,
        action TEXT NOT NULL,  -- 'follow','ignore','','blacklist','unblacklist','follow_blacklist','unfollow_blacklist','follow_muted','unfollow_muted'
        block_num INT NOT NULL,
        op_seq BIGINT NOT NULL  -- global ordering to deduplicate within batch
    ) ON COMMIT DROP;
    TRUNCATE _follow_actions;

    -- ========== PHASE 1: Parse JSON and collect actions ==========
    FOR rec IN
        SELECT
            ho.id AS op_id,
            ho.block_num,
            ho.body->'value' AS val
        FROM hivemind_app.operations_view ho
        WHERE ho.block_num BETWEEN _first_block AND _last_block
          AND ho.op_type_id = 18
          AND ho.custom_json_type_id IN (
              SELECT id FROM hafd.custom_json_types
              WHERE custom_json_id = 'follow'
          )
        ORDER BY ho.id
    LOOP
        _val := rec.val;

        -- Auth validation: required_auths must be empty, required_posting_auths must have exactly 1
        IF jsonb_array_length(COALESCE(_val->'required_auths', '[]'::jsonb)) != 0 THEN
            CONTINUE;
        END IF;
        IF jsonb_array_length(COALESCE(_val->'required_posting_auths', '[]'::jsonb)) != 1 THEN
            CONTINUE;
        END IF;
        _auth_account := _val->'required_posting_auths'->>0;

        -- Parse inner JSON (double-encoded: the 'json' field is a JSON string)
        BEGIN
            _inner_json := (_val->>'json')::jsonb;
        EXCEPTION WHEN OTHERS THEN
            CONTINUE;  -- Invalid JSON, skip
        END;

        -- Legacy compat: if not array and block < 6M, wrap as ['follow', data]
        IF jsonb_typeof(_inner_json) != 'array' THEN
            IF rec.block_num < 6000000 THEN
                _inner_json := jsonb_build_array('follow', _inner_json);
            ELSE
                CONTINUE;
            END IF;
        END IF;

        -- Must be array of length 2
        IF jsonb_array_length(_inner_json) != 2 THEN
            CONTINUE;
        END IF;

        -- First element must be 'follow' (skip 'reblog' — handled by Python)
        IF _inner_json->>0 != 'follow' THEN
            CONTINUE;
        END IF;

        -- Second element must be an object
        _data := _inner_json->1;
        IF jsonb_typeof(_data) != 'object' THEN
            CONTINUE;
        END IF;

        -- Must have 'follower', 'following', 'what' keys; 'what' must be array
        IF NOT (_data ? 'follower' AND _data ? 'following' AND _data ? 'what') THEN
            CONTINUE;
        END IF;
        IF jsonb_typeof(_data->'what') != 'array' THEN
            CONTINUE;
        END IF;

        _what_action := COALESCE(_data->'what'->>0, '');
        _follower_name := _data->>'follower';

        -- Follower must match auth account
        IF _follower_name IS NULL OR _follower_name = '' OR _follower_name != _auth_account THEN
            CONTINUE;
        END IF;

        -- Handle reset actions immediately (they're rare and affect all rows for a follower)
        -- These need follower_id resolved upfront; non-reset actions defer to Phase 2 bulk JOIN
        IF _what_action LIKE 'reset_%' THEN
            SELECT id INTO _follower_id FROM hivemind_app.hive_accounts WHERE name = _follower_name;
            IF _follower_id IS NULL THEN
                CONTINUE;
            END IF;
        END IF;

        IF _what_action = 'reset_blacklist' THEN
            PERFORM hivemind_app.reset_blacklisted(
                ARRAY[ROW(_follower_id, NULL, rec.block_num)::hivemind_app.blacklist_ids]);
            CONTINUE;
        ELSIF _what_action = 'reset_following_list' THEN
            PERFORM hivemind_app.reset_follows(
                ARRAY[ROW(_follower_id, NULL, rec.block_num)::hivemind_app.follow_ids]);
            CONTINUE;
        ELSIF _what_action = 'reset_muted_list' THEN
            PERFORM hivemind_app.reset_muted(
                ARRAY[ROW(_follower_id, NULL, rec.block_num)::hivemind_app.mute_ids]);
            CONTINUE;
        ELSIF _what_action = 'reset_follow_blacklist' THEN
            PERFORM hivemind_app.reset_follow_blacklisted(
                ARRAY[ROW(_follower_id, NULL, rec.block_num)::hivemind_app.follow_blacklist_ids]);
            CONTINUE;
        ELSIF _what_action = 'reset_follow_muted_list' THEN
            PERFORM hivemind_app.reset_follow_muted(
                ARRAY[ROW(_follower_id, NULL, rec.block_num)::hivemind_app.follow_mute_ids]);
            CONTINUE;
        ELSIF _what_action = 'reset_all_lists' THEN
            PERFORM hivemind_app.reset_follows(
                ARRAY[ROW(_follower_id, NULL, rec.block_num)::hivemind_app.follow_ids]);
            PERFORM hivemind_app.reset_muted(
                ARRAY[ROW(_follower_id, NULL, rec.block_num)::hivemind_app.mute_ids]);
            PERFORM hivemind_app.reset_blacklisted(
                ARRAY[ROW(_follower_id, NULL, rec.block_num)::hivemind_app.blacklist_ids]);
            PERFORM hivemind_app.reset_follow_blacklisted(
                ARRAY[ROW(_follower_id, NULL, rec.block_num)::hivemind_app.follow_blacklist_ids]);
            PERFORM hivemind_app.reset_follow_muted(
                ARRAY[ROW(_follower_id, NULL, rec.block_num)::hivemind_app.follow_mute_ids]);
            CONTINUE;
        END IF;

        -- Normalize 'following' to array of names (required for non-reset actions)
        _following_raw := _data->'following';
        IF jsonb_typeof(_following_raw) = 'array' THEN
            SELECT array_agg(elem) INTO _following_arr
            FROM jsonb_array_elements_text(_following_raw) AS elem
            WHERE elem IS NOT NULL AND elem != '' AND elem != _follower_name;
        ELSIF jsonb_typeof(_following_raw) = 'string' THEN
            _following_name := _following_raw #>> '{}';
            IF _following_name IS NOT NULL AND _following_name != '' AND _following_name != _follower_name THEN
                _following_arr := ARRAY[_following_name];
            ELSE
                _following_arr := '{}';
            END IF;
        ELSE
            CONTINUE;
        END IF;

        -- Collect actions into temp table instead of executing DML per-row
        IF _what_action IN ('blog', 'follow', 'ignore', '', 'blacklist', 'unblacklist',
                            'follow_blacklist', 'unfollow_blacklist', 'follow_muted', 'unfollow_muted') THEN
            FOREACH _following_name IN ARRAY COALESCE(_following_arr, '{}') LOOP
                _op_seq := _op_seq + 1;
                INSERT INTO _follow_actions (follower_name, following_name, action, block_num, op_seq)
                VALUES (_follower_name, _following_name, _what_action, rec.block_num, _op_seq);
            END LOOP;
        END IF;
        -- Unknown action types are silently ignored (matching Python behavior)
    END LOOP;

    -- ========== PHASE 2: Bulk DML using set-based operations ==========

    -- Exit early if no actions collected
    IF NOT EXISTS (SELECT 1 FROM _follow_actions LIMIT 1) THEN
        RETURN QUERY SELECT * FROM _follow_notifications;
        RETURN;
    END IF;

    -- 2a. Resolve all names to IDs in bulk and deduplicate:
    --     For each (follower, following) pair, keep only the LAST action (highest op_seq)
    DROP TABLE IF EXISTS _final_actions;
    CREATE TEMP TABLE _final_actions AS
    SELECT DISTINCT ON (fa.follower_name, fa.following_name)
           fr.id AS follower_id, fa.follower_name,
           fo.id AS following_id, fa.following_name,
           fa.action, fa.block_num
    FROM _follow_actions fa
    JOIN hivemind_app.hive_accounts fr ON fr.name = fa.follower_name
    JOIN hivemind_app.hive_accounts fo ON fo.name = fa.following_name
    ORDER BY fa.follower_name, fa.following_name, fa.op_seq DESC;

    -- Add index for efficient lookups in subsequent operations
    CREATE INDEX ON _final_actions (action);

    -- ---- FOLLOW actions ('blog', 'follow') ----

    -- Insert new follows, update block_num for existing ones
    -- Track which ones are genuinely new (for counter updates)
    CREATE TEMP TABLE _new_follows AS
    INSERT INTO hivemind_app.follows (follower, following, block_num)
    SELECT follower_id, following_id, block_num
    FROM _final_actions WHERE action IN ('blog', 'follow')
    ON CONFLICT (follower, following) DO UPDATE SET block_num = EXCLUDED.block_num
    RETURNING follower, following,
              -- xmax = 0 means it was a fresh insert, not an update of existing row
              (xmax = 0) AS is_new;

    -- Delete from muted for all new follows (regardless of whether follow was new or existing)
    DELETE FROM hivemind_app.muted m
    USING _final_actions fa
    WHERE fa.action IN ('blog', 'follow')
      AND m.follower = fa.follower_id AND m.following = fa.following_id;

    -- Update following counters for genuinely new follows
    UPDATE hivemind_app.hive_accounts ha
    SET following = following + delta.cnt
    FROM (SELECT follower, count(*) AS cnt FROM _new_follows WHERE is_new GROUP BY follower) delta
    WHERE ha.id = delta.follower;

    -- Update followers counters for genuinely new follows
    UPDATE hivemind_app.hive_accounts ha
    SET followers = followers + delta.cnt
    FROM (SELECT following, count(*) AS cnt FROM _new_follows WHERE is_new GROUP BY following) delta
    WHERE ha.id = delta.following;

    -- Accumulate follow notifications (for ALL follow actions, not just new ones)
    INSERT INTO _follow_notifications
    SELECT follower_name, following_name, block_num
    FROM _final_actions WHERE action IN ('blog', 'follow');

    DROP TABLE _new_follows;

    -- ---- IGNORE (mute) actions ----

    -- Insert/update muted
    INSERT INTO hivemind_app.muted (follower, following, block_num)
    SELECT follower_id, following_id, block_num
    FROM _final_actions WHERE action = 'ignore'
    ON CONFLICT (follower, following) DO UPDATE SET block_num = EXCLUDED.block_num;

    -- Delete from follows + track which were actually deleted (for counter updates)
    CREATE TEMP TABLE _deleted_follows_ignore AS
    DELETE FROM hivemind_app.follows f
    USING _final_actions fa
    WHERE fa.action = 'ignore'
      AND f.follower = fa.follower_id AND f.following = fa.following_id
    RETURNING f.follower, f.following;

    -- Decrement following counters
    UPDATE hivemind_app.hive_accounts ha
    SET following = following - delta.cnt
    FROM (SELECT follower, count(*) AS cnt FROM _deleted_follows_ignore GROUP BY follower) delta
    WHERE ha.id = delta.follower;

    -- Decrement followers counters
    UPDATE hivemind_app.hive_accounts ha
    SET followers = followers - delta.cnt
    FROM (SELECT following, count(*) AS cnt FROM _deleted_follows_ignore GROUP BY following) delta
    WHERE ha.id = delta.following;

    DROP TABLE _deleted_follows_ignore;

    -- ---- UNFOLLOW actions (action = '') ----

    -- Delete from follows + track deletions for counter updates
    CREATE TEMP TABLE _deleted_follows_unfollow AS
    DELETE FROM hivemind_app.follows f
    USING _final_actions fa
    WHERE fa.action = ''
      AND f.follower = fa.follower_id AND f.following = fa.following_id
    RETURNING f.follower, f.following;

    -- Decrement following counters
    UPDATE hivemind_app.hive_accounts ha
    SET following = following - delta.cnt
    FROM (SELECT follower, count(*) AS cnt FROM _deleted_follows_unfollow GROUP BY follower) delta
    WHERE ha.id = delta.follower;

    -- Decrement followers counters
    UPDATE hivemind_app.hive_accounts ha
    SET followers = followers - delta.cnt
    FROM (SELECT following, count(*) AS cnt FROM _deleted_follows_unfollow GROUP BY following) delta
    WHERE ha.id = delta.following;

    DROP TABLE _deleted_follows_unfollow;

    -- Delete from muted for unfollow actions
    DELETE FROM hivemind_app.muted m
    USING _final_actions fa
    WHERE fa.action = ''
      AND m.follower = fa.follower_id AND m.following = fa.following_id;

    -- ---- BLACKLIST actions ----

    INSERT INTO hivemind_app.blacklisted (follower, following, block_num)
    SELECT follower_id, following_id, block_num
    FROM _final_actions WHERE action = 'blacklist'
    ON CONFLICT (follower, following) DO UPDATE SET block_num = EXCLUDED.block_num;

    -- ---- UNBLACKLIST actions ----

    DELETE FROM hivemind_app.blacklisted b
    USING _final_actions fa
    WHERE fa.action = 'unblacklist'
      AND b.follower = fa.follower_id AND b.following = fa.following_id;

    -- ---- FOLLOW_BLACKLIST actions ----

    INSERT INTO hivemind_app.follow_blacklisted (follower, following, block_num)
    SELECT follower_id, following_id, block_num
    FROM _final_actions WHERE action = 'follow_blacklist'
    ON CONFLICT (follower, following) DO UPDATE SET block_num = EXCLUDED.block_num;

    -- ---- UNFOLLOW_BLACKLIST actions ----

    DELETE FROM hivemind_app.follow_blacklisted fb
    USING _final_actions fa
    WHERE fa.action = 'unfollow_blacklist'
      AND fb.follower = fa.follower_id AND fb.following = fa.following_id;

    -- ---- FOLLOW_MUTED actions ----

    INSERT INTO hivemind_app.follow_muted (follower, following, block_num)
    SELECT follower_id, following_id, block_num
    FROM _final_actions WHERE action = 'follow_muted'
    ON CONFLICT (follower, following) DO UPDATE SET block_num = EXCLUDED.block_num;

    -- ---- UNFOLLOW_MUTED actions ----

    DELETE FROM hivemind_app.follow_muted fm
    USING _final_actions fa
    WHERE fa.action = 'unfollow_muted'
      AND fm.follower = fa.follower_id AND fm.following = fa.following_id;

    DROP TABLE _final_actions;
    DROP TABLE _follow_actions;

    -- Return notification data for Follow actions
    RETURN QUERY SELECT * FROM _follow_notifications;
END
$function$
    LANGUAGE plpgsql VOLATILE
;


DROP TYPE IF EXISTS hivemind_app.hivemind_block_date CASCADE;
CREATE TYPE hivemind_app.hivemind_block_date AS (
    num INT,
    date TEXT
);

CREATE OR REPLACE FUNCTION hivemind_app.get_block_dates_for_hivemind(in _first_block INT, in _last_block INT)
    RETURNS SETOF hivemind_app.hivemind_block_date
AS
$function$
BEGIN
    RETURN QUERY
        SELECT
            hb.num,
            to_char( hb.created_at, 'YYYY-MM-DDThh24:MI:SS' )
        FROM hivemind_app.blocks_view hb
        WHERE hb.num BETWEEN _first_block AND _last_block
        ORDER BY hb.num
    ;
END
$function$
    LANGUAGE plpgsql STABLE
;

--- Extended flat-row function with extracted vote fields ---

DROP TYPE IF EXISTS hivemind_app.hivemind_flat_op_extended CASCADE;
CREATE TYPE hivemind_app.hivemind_flat_op_extended AS (
    block_num INT,
    op_type_id INT,
    body JSONB,
    -- Extracted fields for vote (0) and effective_comment_vote (72) ops.
    -- NULL for all other op types.
    f_voter TEXT,
    f_author TEXT,
    f_permlink TEXT,
    f_weight NUMERIC,
    f_rshares NUMERIC,
    f_pending_payout JSONB,
    f_total_vote_weight NUMERIC
);

CREATE OR REPLACE FUNCTION hivemind_app.get_ops_for_hivemind_v2(in _first_block INT, in _last_block INT)
    RETURNS SETOF hivemind_app.hivemind_flat_op_extended
AS
$function$
BEGIN
    /** Like get_ops_for_hivemind but extracts vote fields as separate columns.
        For vote (0) and effective_comment_vote (72) ops, body is NULL and the
        individual fields are populated. For all other ops, body contains the
        inner 'value' payload and the field columns are NULL.

        Uses a CTE so body_binary::jsonb->'value' is computed exactly once per row.
    */
    RETURN QUERY
        WITH op_values AS (
            SELECT ho.id, ho.block_num, ho.op_type_id, ho.body->'value' as val
            FROM hivemind_app.operations_view ho
            WHERE ho.block_num BETWEEN _first_block AND _last_block
              AND ho.op_type_id IN (0,1,9,10,14,17,18,19,23,30,41,43, 51,53,61,72,73)
              AND (ho.op_type_id != 18
                OR ho.custom_json_type_id IN (
                    SELECT id FROM hafd.custom_json_types
                    WHERE custom_json_id IN ('follow', 'reblog', 'community', 'notify')
                ))
        )
        SELECT
            ov.block_num,
            ov.op_type_id,
            CASE WHEN ov.op_type_id NOT IN (0, 72) THEN ov.val END,
            CASE WHEN ov.op_type_id IN (0, 72) THEN ov.val->>'voter' END,
            CASE WHEN ov.op_type_id IN (0, 72) THEN ov.val->>'author' END,
            CASE WHEN ov.op_type_id IN (0, 72) THEN ov.val->>'permlink' END,
            CASE WHEN ov.op_type_id IN (0, 72) THEN (ov.val->>'weight')::NUMERIC END,
            CASE WHEN ov.op_type_id = 72 THEN (ov.val->>'rshares')::NUMERIC END,
            CASE WHEN ov.op_type_id = 72 THEN ov.val->'pending_payout' END,
            CASE WHEN ov.op_type_id = 72 THEN (ov.val->>'total_vote_weight')::NUMERIC END
        FROM op_values ov
        ORDER BY ov.id
    ;
END
$function$
    LANGUAGE plpgsql STABLE
;

--- Combined single-query: extended ops with block dates in one round-trip ---

DROP TYPE IF EXISTS hivemind_app.hivemind_flat_op_extended_with_date CASCADE;
CREATE TYPE hivemind_app.hivemind_flat_op_extended_with_date AS (
    block_num INT,
    date TEXT,
    op_type_id INT,
    body JSONB,
    f_voter TEXT,
    f_author TEXT,
    f_permlink TEXT,
    f_weight NUMERIC,
    f_rshares NUMERIC,
    f_pending_payout JSONB,
    f_total_vote_weight NUMERIC
);

CREATE OR REPLACE FUNCTION hivemind_app.get_blocks_and_ops_for_hivemind_v2(in _first_block INT, in _last_block INT)
    RETURNS SETOF hivemind_app.hivemind_flat_op_extended_with_date
AS
$function$
BEGIN
    /** Combined single-query: returns block date with each operation row, including
        extracted vote fields. Blocks with no operations get a single row with
        op_type_id = NULL (LEFT JOIN). Ordered by block_num, then operation id.

        Like get_ops_for_hivemind_v2 but includes block dates, eliminating the
        need for a separate get_block_dates_for_hivemind() call.
    */
    RETURN QUERY
        WITH op_values AS (
            SELECT ho.id, ho.block_num, ho.op_type_id, ho.body->'value' as val
            FROM hivemind_app.operations_view ho
            WHERE ho.block_num BETWEEN _first_block AND _last_block
              AND ho.op_type_id IN (0,1,9,10,14,17,18,19,23,30,41,43, 51,53,61,72,73)
              AND (ho.op_type_id != 18
                OR ho.custom_json_type_id IN (
                    SELECT id FROM hafd.custom_json_types
                    WHERE custom_json_id IN ('follow', 'reblog', 'community', 'notify')
                ))
        )
        SELECT
            hb.num,
            to_char( hb.created_at, 'YYYY-MM-DDThh24:MI:SS' ),
            ov.op_type_id,
            CASE WHEN ov.op_type_id NOT IN (0, 72) THEN ov.val END,
            CASE WHEN ov.op_type_id IN (0, 72) THEN ov.val->>'voter' END,
            CASE WHEN ov.op_type_id IN (0, 72) THEN ov.val->>'author' END,
            CASE WHEN ov.op_type_id IN (0, 72) THEN ov.val->>'permlink' END,
            CASE WHEN ov.op_type_id IN (0, 72) THEN (ov.val->>'weight')::NUMERIC END,
            CASE WHEN ov.op_type_id = 72 THEN (ov.val->>'rshares')::NUMERIC END,
            CASE WHEN ov.op_type_id = 72 THEN ov.val->'pending_payout' END,
            CASE WHEN ov.op_type_id = 72 THEN (ov.val->>'total_vote_weight')::NUMERIC END
        FROM hivemind_app.blocks_view hb
        LEFT JOIN op_values ov ON ov.block_num = hb.num
        WHERE hb.num BETWEEN _first_block AND _last_block
        ORDER BY hb.num, ov.id
    ;
END
$function$
    LANGUAGE plpgsql STABLE
;

