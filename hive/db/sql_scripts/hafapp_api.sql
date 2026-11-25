--- Flat-row functions for sync (no ARRAY_AGG, no type wrapper, no hash/prev) ---

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

        Body is returned as body_value (the inner payload, no type wrapper).
    */
    RETURN QUERY
        SELECT
            ho.block_num,
            ho.op_type_id,
            ho.body_value
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

-- A reset of list _list (1: muted, 2: follow_muted) of _follower_id, about to delete its
-- rows, into process_follows_for_blocks' _mute_actions: the rows as they are (the state
-- before the phase, when this is the follower's first reset of the list), then the reset.
DROP FUNCTION IF EXISTS hivemind_app.record_mute_reset(SMALLINT, TEXT, INT, INT, BIGINT);
CREATE OR REPLACE FUNCTION hivemind_app.record_mute_reset(
    _list SMALLINT, _follower_name TEXT, _follower_id INT, _block_num INT, _op_seq BIGINT,
    _accounts_until TIMESTAMP
) RETURNS VOID AS $function$
BEGIN
    INSERT INTO _mute_actions (list, follower_name, following_id, block_num, op_seq, is_set, accounts_until)
    SELECT _list, _follower_name, l.following, 0, 0, TRUE, _accounts_until
    FROM (
        SELECT m.following FROM hivemind_app.muted m WHERE _list = 1 AND m.follower = _follower_id
        UNION ALL
        SELECT fm.following FROM hivemind_app.follow_muted fm WHERE _list = 2 AND fm.follower = _follower_id
    ) l;

    INSERT INTO _mute_actions (list, follower_name, block_num, op_seq, is_set, accounts_until)
    VALUES (_list, _follower_name, _block_num, _op_seq, FALSE, _accounts_until);
END
$function$ LANGUAGE plpgsql VOLATILE;

-- Replaces _batch_mute_changes with the changes of process_follows_for_blocks'
-- _mute_actions; runs before that phase applies them, so a list row of a pair no reset
-- captured is the state before the phase. Only pairs on a list at some point are kept:
-- the others (a follow of an account never muted) are off the list throughout. Accounts
-- that do not exist by the action's block are skipped, as the phase skips their actions.
DROP FUNCTION IF EXISTS hivemind_app.record_batch_mute_changes(TIMESTAMP);
CREATE OR REPLACE FUNCTION hivemind_app.record_batch_mute_changes()
RETURNS VOID AS $function$
BEGIN
    DELETE FROM hivemind_app._batch_mute_changes;

    INSERT INTO hivemind_app._batch_mute_changes (list, follower, following, block_num, op_seq, is_set)
    WITH actions AS MATERIALIZED (
        SELECT a.list, fr.id AS follower, COALESCE(a.following_id, fo.id) AS following,
               a.block_num, a.op_seq, a.is_set
        FROM _mute_actions a
        JOIN hivemind_app.hive_accounts fr ON fr.name = a.follower_name AND fr.created_at <= a.accounts_until
        LEFT JOIN hivemind_app.hive_accounts fo ON fo.name = a.following_name AND fo.created_at <= a.accounts_until
        WHERE a.following_name IS NULL OR fo.id IS NOT NULL
    ),
    pairs AS MATERIALIZED (
        SELECT p.list, p.follower, p.following, p.listed_now
        FROM (
            SELECT a.list, a.follower, a.following, bool_or(a.is_set) AS set_in_phase,
                   CASE a.list
                       WHEN 1 THEN EXISTS (SELECT 1 FROM hivemind_app.muted m
                                           WHERE m.follower = a.follower AND m.following = a.following)
                       ELSE EXISTS (SELECT 1 FROM hivemind_app.follow_muted fm
                                    WHERE fm.follower = a.follower AND fm.following = a.following)
                   END AS listed_now
            FROM actions a
            WHERE a.following IS NOT NULL
            GROUP BY a.list, a.follower, a.following
        ) p
        WHERE p.set_in_phase OR p.listed_now
    )
    SELECT a.list, a.follower, a.following, a.block_num, a.op_seq, a.is_set
    FROM actions a
    JOIN pairs p ON p.list = a.list AND p.follower = a.follower AND p.following = a.following
    UNION ALL
    -- a reset clears every pair of the follower's list
    SELECT p.list, p.follower, p.following, r.block_num, r.op_seq, FALSE
    FROM actions r
    JOIN pairs p ON p.list = r.list AND p.follower = r.follower
    WHERE r.following IS NULL
    UNION ALL
    SELECT p.list, p.follower, p.following, 0, 0, p.listed_now
    FROM pairs p
    WHERE NOT EXISTS (SELECT 1 FROM actions c
                      WHERE c.list = p.list AND c.follower = p.follower AND c.following = p.following
                        AND c.block_num = 0);
END
$function$ LANGUAGE plpgsql VOLATILE;

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
    -- A replay of a batch whose follows phase committed keeps the mute changes it
    -- recorded: the lists now hold the state after them.
    _record_mutes BOOLEAN := NOT EXISTS (SELECT 1 FROM hivemind_app._batch_queue
                                         WHERE first_block = _first_block AND follows_applied);
BEGIN
    -- The events of the last follows phase are read by its notification flush, which runs
    -- before the next follows phase.
    DELETE FROM hivemind_app._follow_notification_events;

    CREATE TEMP TABLE IF NOT EXISTS _follow_notifications (
        follower_name TEXT,
        following_name TEXT,
        block_num INT,
        op_seq BIGINT
    ) ON COMMIT DROP;

    -- Temp table for collecting parsed follow actions (Phase 1 output)
    CREATE TEMP TABLE IF NOT EXISTS _follow_actions (
        follower_name TEXT NOT NULL,
        following_name TEXT NOT NULL,
        action TEXT NOT NULL,  -- 'follow','ignore','','blacklist','unblacklist','follow_blacklist','unfollow_blacklist','follow_muted','unfollow_muted'
        block_num INT NOT NULL,
        op_seq BIGINT NOT NULL,  -- global ordering to deduplicate within batch
        accounts_until TIMESTAMP NOT NULL
    ) ON COMMIT DROP;
    TRUNCATE _follow_actions;

    -- Every action on the muted (list 1) and follow_muted (list 2) lists, in order, for
    -- record_batch_mute_changes; a reset is a row without a following.
    CREATE TEMP TABLE IF NOT EXISTS _mute_actions (
        list SMALLINT NOT NULL,
        follower_name TEXT NOT NULL,
        following_name TEXT,
        following_id INT,
        block_num INT NOT NULL,
        op_seq BIGINT NOT NULL,
        is_set BOOLEAN NOT NULL,
        accounts_until TIMESTAMP NOT NULL
    ) ON COMMIT DROP;
    TRUNCATE _mute_actions;

    -- ========== PHASE 1: Parse JSON and collect actions ==========
    -- The batch's operations as Stage B reads them (_ops_staging_b), not the context's
    -- operations_view, which the next batch's iteration recreates while pipelined massive
    -- sync runs this.
    -- An action sees the accounts that exist at the end of its own block, as live sync does
    -- whatever the batch: the ops of block b, account creations included, carry the date of
    -- block b - 1 (load_ops_staging), which is hive_accounts.created_at of an account created
    -- in b, and blocks are dated strictly in order. Pipelined massive sync runs this after
    -- the next batch's Stage A has registered that batch's accounts.
    FOR rec IN
        SELECT
            s.id AS op_id,
            s.block_num,
            s.block_date AS accounts_until,
            s.val
        FROM hivemind_app._ops_staging_b s
        WHERE s.block_num BETWEEN _first_block AND _last_block
          AND s.op_type_id = 18
          AND s.val->>'id' = 'follow'
        ORDER BY s.id
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
        -- PostgreSQL ->> converts boolean false/true to text 'false'/'true';
        -- normalize to '' (= unfollow/unmute) to match Python's `False or '' → ''`.
        IF _what_action IN ('false', 'true') THEN
            _what_action := '';
        END IF;
        _follower_name := _data->>'follower';

        -- Follower must match auth account
        IF _follower_name IS NULL OR _follower_name = '' OR _follower_name != _auth_account THEN
            CONTINUE;
        END IF;

        -- Handle reset actions immediately (they're rare and affect all rows for a follower)
        -- These need follower_id resolved upfront; non-reset actions defer to Phase 2 bulk JOIN
        IF _what_action LIKE 'reset_%' THEN
            SELECT id INTO _follower_id FROM hivemind_app.hive_accounts
            WHERE name = _follower_name AND created_at <= rec.accounts_until;
            IF _follower_id IS NULL THEN
                CONTINUE;
            END IF;
        END IF;

        IF _what_action = 'reset_blacklist' THEN
            PERFORM hivemind_app.reset_blacklisted(
                ARRAY[ROW(_follower_id, NULL, rec.block_num)::hivemind_app.blacklist_ids]);
            DELETE FROM _follow_actions WHERE follower_name = _follower_name
                AND action IN ('blacklist', 'unblacklist');
            CONTINUE;
        ELSIF _what_action = 'reset_following_list' THEN
            PERFORM hivemind_app.reset_follows(
                ARRAY[ROW(_follower_id, NULL, rec.block_num)::hivemind_app.follow_ids]);
            DELETE FROM _follow_actions WHERE follower_name = _follower_name
                AND action IN ('blog', 'follow');
            CONTINUE;
        ELSIF _what_action = 'reset_muted_list' THEN
            _op_seq := _op_seq + 1;
            PERFORM hivemind_app.record_mute_reset(1::SMALLINT, _follower_name, _follower_id, rec.block_num, _op_seq, rec.accounts_until);
            PERFORM hivemind_app.reset_muted(
                ARRAY[ROW(_follower_id, NULL, rec.block_num)::hivemind_app.mute_ids]);
            DELETE FROM _follow_actions WHERE follower_name = _follower_name
                AND action = 'ignore';
            CONTINUE;
        ELSIF _what_action = 'reset_follow_blacklist' THEN
            PERFORM hivemind_app.reset_follow_blacklisted(
                ARRAY[ROW(_follower_id, NULL, rec.block_num)::hivemind_app.follow_blacklist_ids]);
            DELETE FROM _follow_actions WHERE follower_name = _follower_name
                AND action IN ('follow_blacklist', 'unfollow_blacklist');
            CONTINUE;
        ELSIF _what_action = 'reset_follow_muted_list' THEN
            _op_seq := _op_seq + 1;
            PERFORM hivemind_app.record_mute_reset(2::SMALLINT, _follower_name, _follower_id, rec.block_num, _op_seq, rec.accounts_until);
            PERFORM hivemind_app.reset_follow_muted(
                ARRAY[ROW(_follower_id, NULL, rec.block_num)::hivemind_app.follow_mute_ids]);
            DELETE FROM _follow_actions WHERE follower_name = _follower_name
                AND action IN ('follow_muted', 'unfollow_muted');
            CONTINUE;
        ELSIF _what_action = 'reset_all_lists' THEN
            _op_seq := _op_seq + 1;
            PERFORM hivemind_app.record_mute_reset(1::SMALLINT, _follower_name, _follower_id, rec.block_num, _op_seq, rec.accounts_until);
            PERFORM hivemind_app.record_mute_reset(2::SMALLINT, _follower_name, _follower_id, rec.block_num, _op_seq, rec.accounts_until);
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
            DELETE FROM _follow_actions WHERE follower_name = _follower_name;
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
                INSERT INTO _follow_actions (follower_name, following_name, action, block_num, op_seq, accounts_until)
                VALUES (_follower_name, _following_name, _what_action, rec.block_num, _op_seq, rec.accounts_until);
                -- ignore mutes; follow, blog and '' unmute (Phase 2 deletes their muted row)
                IF _what_action IN ('ignore', 'blog', 'follow', '', 'follow_muted', 'unfollow_muted') THEN
                    INSERT INTO _mute_actions (list, follower_name, following_name, block_num, op_seq, is_set, accounts_until)
                    VALUES (CASE WHEN _what_action LIKE '%follow_muted' THEN 2 ELSE 1 END,
                            _follower_name, _following_name, rec.block_num, _op_seq,
                            _what_action IN ('ignore', 'follow_muted'), rec.accounts_until);
                END IF;
                -- Collect follow notifications inline (Phase 1) to match old Python path where
                -- every follow/blog op generates a notification before dedup, preserving counter values
                IF _what_action IN ('blog', 'follow') THEN
                    INSERT INTO _follow_notifications (follower_name, following_name, block_num, op_seq)
                    VALUES (_follower_name, _following_name, rec.block_num, _op_seq);
                END IF;
            END LOOP;
        END IF;
        -- Unknown action types are silently ignored (matching Python behavior)
    END LOOP;

    -- Before Phase 2 applies the actions: the lists still hold the state before them,
    -- but for the resets, which record_mute_reset captured.
    IF _record_mutes THEN
        PERFORM hivemind_app.record_batch_mute_changes();
    END IF;
    UPDATE hivemind_app._batch_queue SET follows_applied = TRUE WHERE first_block = _first_block;

    -- ========== PHASE 2: Bulk DML using set-based operations ==========

    -- Exit early if no actions collected
    IF NOT EXISTS (SELECT 1 FROM _follow_actions LIMIT 1) THEN
        -- Persist follow events for notification flush (survives cross-connection Phase 4→6)
        INSERT INTO hivemind_app._follow_notification_events (follower_name, following_name, block_num, op_seq)
        SELECT fn.follower_name, fn.following_name, fn.block_num, fn.op_seq FROM _follow_notifications fn;
        RETURN QUERY SELECT follower_name, following_name, block_num FROM _follow_notifications ORDER BY block_num, op_seq;
        RETURN;
    END IF;

    -- 2a. Resolve all names to IDs in bulk and deduplicate per action group.
    --     Different action groups target different tables and are independent:
    --       - follow group: blog/follow, ignore, '' (mutually exclusive)
    --       - blacklist group: blacklist, unblacklist
    --       - follow_blacklist group: follow_blacklist, unfollow_blacklist
    --       - follow_muted group: follow_muted, unfollow_muted
    --     Within each group, for each (follower, following) pair keep only the LAST action
    --     of those whose accounts exist by the action's block: one of an account that does
    --     not exist yet never takes effect, nor hides an earlier one.
    DROP TABLE IF EXISTS _final_actions;
    CREATE TEMP TABLE _final_actions AS
    WITH action_groups AS (
        SELECT fa.follower_name, fa.following_name, fa.action, fa.block_num, fa.op_seq,
               fr.id AS follower_id, fo.id AS following_id,
               CASE
                   WHEN fa.action IN ('blog', 'follow', 'ignore', '') THEN 'follow_group'
                   WHEN fa.action IN ('blacklist', 'unblacklist') THEN 'blacklist_group'
                   WHEN fa.action IN ('follow_blacklist', 'unfollow_blacklist') THEN 'follow_blacklist_group'
                   WHEN fa.action IN ('follow_muted', 'unfollow_muted') THEN 'follow_muted_group'
               END AS action_group
        FROM _follow_actions fa
        JOIN hivemind_app.hive_accounts fr ON fr.name = fa.follower_name AND fr.created_at <= fa.accounts_until
        JOIN hivemind_app.hive_accounts fo ON fo.name = fa.following_name AND fo.created_at <= fa.accounts_until
    )
    SELECT DISTINCT ON (ag.follower_name, ag.following_name, ag.action_group)
           ag.follower_id, ag.follower_name,
           ag.following_id, ag.following_name,
           ag.action, ag.block_num, ag.op_seq
    FROM action_groups ag
    ORDER BY ag.follower_name, ag.following_name, ag.action_group, ag.op_seq DESC;

    -- Add index for efficient lookups in subsequent operations
    CREATE INDEX ON _final_actions (action);

    -- ---- FOLLOW actions ('blog', 'follow') ----

    -- Insert new follows, update block_num for existing ones
    -- Track which ones are genuinely new (for counter updates)
    CREATE TEMP TABLE _new_follows AS
    WITH ins AS (
        INSERT INTO hivemind_app.follows (follower, following, block_num, follower_name)
        SELECT follower_id, following_id, block_num, follower_name
        FROM _final_actions WHERE action IN ('blog', 'follow')
        ON CONFLICT (follower, following) DO UPDATE SET block_num = EXCLUDED.block_num
        RETURNING follower, following,
                  -- xmax = 0 means it was a fresh insert, not an update of existing row
                  (xmax = 0) AS is_new
    ) SELECT * FROM ins;

    -- Delete from muted for all new follows (regardless of whether follow was new or existing)
    DELETE FROM hivemind_app.muted m
    USING _final_actions fa
    WHERE fa.action IN ('blog', 'follow')
      AND m.follower = fa.follower_id AND m.following = fa.following_id;

    -- Update following counters for genuinely new follows
    -- The locked CTE pre-locks hive_accounts rows in id order to prevent deadlocks
    -- when concurrent transactions (e.g. process_account_updates) lock the same rows.
    -- The UPDATE reads its counts from locked: PostgreSQL never runs an unreferenced SELECT CTE.
    WITH delta AS (
        SELECT follower AS account_id, count(*) AS cnt FROM _new_follows WHERE is_new GROUP BY follower
    ),
    locked AS (
        SELECT ha.id, d.cnt FROM hivemind_app.hive_accounts ha
        JOIN delta d ON ha.id = d.account_id ORDER BY ha.id FOR UPDATE OF ha
    )
    UPDATE hivemind_app.hive_accounts ha
    SET following = following + locked.cnt
    FROM locked WHERE ha.id = locked.id;

    -- Update followers counters for genuinely new follows
    WITH delta AS (
        SELECT following AS account_id, count(*) AS cnt FROM _new_follows WHERE is_new GROUP BY following
    ),
    locked AS (
        SELECT ha.id, d.cnt FROM hivemind_app.hive_accounts ha
        JOIN delta d ON ha.id = d.account_id ORDER BY ha.id FOR UPDATE OF ha
    )
    UPDATE hivemind_app.hive_accounts ha
    SET followers = followers + locked.cnt
    FROM locked WHERE ha.id = locked.id;

    -- Follow notifications were already collected in Phase 1 (inline with _follow_actions)
    -- to match old Python path's per-operation notification generation before dedup.

    DROP TABLE _new_follows;

    -- ---- IGNORE (mute) actions ----

    -- Insert/update muted
    INSERT INTO hivemind_app.muted (follower, following, block_num)
    SELECT follower_id, following_id, block_num
    FROM _final_actions WHERE action = 'ignore'
    ON CONFLICT (follower, following) DO UPDATE SET block_num = EXCLUDED.block_num;

    -- Delete from follows + track which were actually deleted (for counter updates)
    CREATE TEMP TABLE _deleted_follows_ignore AS
    WITH del AS (
        DELETE FROM hivemind_app.follows f
        USING _final_actions fa
        WHERE fa.action = 'ignore'
          AND f.follower = fa.follower_id AND f.following = fa.following_id
        RETURNING f.follower, f.following
    ) SELECT * FROM del;

    -- Decrement following counters (deterministic lock order to prevent deadlocks)
    WITH delta AS (
        SELECT follower AS account_id, count(*) AS cnt FROM _deleted_follows_ignore GROUP BY follower
    ),
    locked AS (
        SELECT ha.id, d.cnt FROM hivemind_app.hive_accounts ha
        JOIN delta d ON ha.id = d.account_id ORDER BY ha.id FOR UPDATE OF ha
    )
    UPDATE hivemind_app.hive_accounts ha
    SET following = following - locked.cnt
    FROM locked WHERE ha.id = locked.id;

    -- Decrement followers counters (deterministic lock order to prevent deadlocks)
    WITH delta AS (
        SELECT following AS account_id, count(*) AS cnt FROM _deleted_follows_ignore GROUP BY following
    ),
    locked AS (
        SELECT ha.id, d.cnt FROM hivemind_app.hive_accounts ha
        JOIN delta d ON ha.id = d.account_id ORDER BY ha.id FOR UPDATE OF ha
    )
    UPDATE hivemind_app.hive_accounts ha
    SET followers = followers - locked.cnt
    FROM locked WHERE ha.id = locked.id;

    DROP TABLE _deleted_follows_ignore;

    -- ---- UNFOLLOW actions (action = '') ----

    -- Delete from follows + track deletions for counter updates
    CREATE TEMP TABLE _deleted_follows_unfollow AS
    WITH del AS (
        DELETE FROM hivemind_app.follows f
        USING _final_actions fa
        WHERE fa.action = ''
          AND f.follower = fa.follower_id AND f.following = fa.following_id
        RETURNING f.follower, f.following
    ) SELECT * FROM del;

    -- Decrement following counters (deterministic lock order to prevent deadlocks)
    WITH delta AS (
        SELECT follower AS account_id, count(*) AS cnt FROM _deleted_follows_unfollow GROUP BY follower
    ),
    locked AS (
        SELECT ha.id, d.cnt FROM hivemind_app.hive_accounts ha
        JOIN delta d ON ha.id = d.account_id ORDER BY ha.id FOR UPDATE OF ha
    )
    UPDATE hivemind_app.hive_accounts ha
    SET following = following - locked.cnt
    FROM locked WHERE ha.id = locked.id;

    -- Decrement followers counters (deterministic lock order to prevent deadlocks)
    WITH delta AS (
        SELECT following AS account_id, count(*) AS cnt FROM _deleted_follows_unfollow GROUP BY following
    ),
    locked AS (
        SELECT ha.id, d.cnt FROM hivemind_app.hive_accounts ha
        JOIN delta d ON ha.id = d.account_id ORDER BY ha.id FOR UPDATE OF ha
    )
    UPDATE hivemind_app.hive_accounts ha
    SET followers = followers - locked.cnt
    FROM locked WHERE ha.id = locked.id;

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

    -- Persist follow events for notification flush (survives cross-connection Phase 4→6)
    INSERT INTO hivemind_app._follow_notification_events (follower_name, following_name, block_num, op_seq)
    SELECT fn.follower_name, fn.following_name, fn.block_num, fn.op_seq FROM _follow_notifications fn;

    -- Return notification data for Follow actions (ordered by block_num for correct
    -- notification counter generation in Python's UniqueCounter)
    RETURN QUERY SELECT follower_name, following_name, block_num FROM _follow_notifications ORDER BY block_num, op_seq;
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

        Uses a CTE so body_value is computed exactly once per row.
    */
    RETURN QUERY
        WITH op_values AS (
            SELECT ho.id, ho.block_num, ho.op_type_id, ho.body_value as val
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
            SELECT ho.id, ho.block_num, ho.op_type_id, ho.body_value as val
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

