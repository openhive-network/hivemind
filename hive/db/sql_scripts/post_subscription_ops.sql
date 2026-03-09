-- Post subscription operations: subscribe/unsubscribe to posts

-- Types for batch operations
DROP TYPE IF EXISTS hivemind_app.post_subscription_op CASCADE;
CREATE TYPE hivemind_app.post_subscription_op AS (
    subscriber_id INTEGER,
    author VARCHAR,
    permlink VARCHAR,
    block_num INTEGER,
    block_date TIMESTAMP
);

DROP TYPE IF EXISTS hivemind_app.post_unsubscription_op CASCADE;
CREATE TYPE hivemind_app.post_unsubscription_op AS (
    subscriber_id INTEGER,
    author VARCHAR,
    permlink VARCHAR,
    block_num INTEGER
);

-- Batch flush function for SUBSCRIBES only
-- Unsubscribes are processed separately AFTER notification generation
-- This allows notifications to be generated for comments created between subscribe and unsubscribe
DROP FUNCTION IF EXISTS hivemind_app.flush_post_subscriptions(hivemind_app.post_subscription_op[], hivemind_app.post_unsubscription_op[]);
DROP FUNCTION IF EXISTS hivemind_app.flush_post_subscribes(hivemind_app.post_subscription_op[]);
CREATE OR REPLACE FUNCTION hivemind_app.flush_post_subscribes(
    _subscribe_ops hivemind_app.post_subscription_op[]
) RETURNS INTEGER AS $$
DECLARE
    _max_subscriptions CONSTANT INTEGER := 16;
    _inserted INTEGER := 0;
BEGIN
    IF array_length(_subscribe_ops, 1) > 0 THEN
        WITH subscriber_counts AS (
            SELECT account_id, COUNT(*) as cnt
            FROM hivemind_app.hive_post_subscriptions
            WHERE account_id IN (SELECT DISTINCT subscriber_id FROM unnest(_subscribe_ops))
            GROUP BY account_id
        ),
        valid_ops AS (
            SELECT DISTINCT ON (op.subscriber_id, hp.id)
                op.subscriber_id,
                hp.id as post_id,
                op.block_date,
                op.block_num
            FROM unnest(_subscribe_ops) op
            JOIN hivemind_app.hive_accounts ha ON ha.name = op.author
            JOIN hivemind_app.hive_permlink_data hpd ON hpd.permlink = op.permlink
            JOIN hivemind_app.hive_posts hp ON hp.author_id = ha.id AND hp.permlink_id = hpd.id AND hp.counter_deleted = 0
            LEFT JOIN subscriber_counts sc ON sc.account_id = op.subscriber_id
            WHERE NOT EXISTS (
                SELECT 1 FROM hivemind_app.hive_post_subscriptions s
                WHERE s.account_id = op.subscriber_id AND s.post_id = hp.id
            )
            AND COALESCE(sc.cnt, 0) < _max_subscriptions
        )
        INSERT INTO hivemind_app.hive_post_subscriptions (account_id, post_id, created_at, block_num)
        SELECT subscriber_id, post_id, block_date, block_num
        FROM valid_ops
        ON CONFLICT (account_id, post_id) DO NOTHING;

        GET DIAGNOSTICS _inserted = ROW_COUNT;
    END IF;

    RETURN _inserted;
END;
$$ LANGUAGE plpgsql;

-- Batch flush function for UNSUBSCRIBES only
-- Called AFTER notification generation to ensure notifications are sent for comments
-- created between subscribe and unsubscribe
DROP FUNCTION IF EXISTS hivemind_app.flush_post_unsubscribes(hivemind_app.post_unsubscription_op[]);
CREATE OR REPLACE FUNCTION hivemind_app.flush_post_unsubscribes(
    _unsubscribe_ops hivemind_app.post_unsubscription_op[]
) RETURNS INTEGER AS $$
DECLARE
    _deleted INTEGER := 0;
BEGIN
    IF array_length(_unsubscribe_ops, 1) > 0 THEN
        DELETE FROM hivemind_app.hive_post_subscriptions hps
        USING (
            SELECT
                op.subscriber_id,
                hp.id as post_id
            FROM unnest(_unsubscribe_ops) op
            JOIN hivemind_app.hive_accounts ha ON ha.name = op.author
            JOIN hivemind_app.hive_permlink_data hpd ON hpd.permlink = op.permlink
            JOIN hivemind_app.hive_posts hp ON hp.author_id = ha.id AND hp.permlink_id = hpd.id AND hp.counter_deleted = 0
        ) AS ops
        WHERE hps.account_id = ops.subscriber_id AND hps.post_id = ops.post_id;

        GET DIAGNOSTICS _deleted = ROW_COUNT;
    END IF;

    RETURN _deleted;
END;
$$ LANGUAGE plpgsql;


DROP FUNCTION IF EXISTS hivemind_app.subscribe_to_post(INTEGER, VARCHAR, VARCHAR, INTEGER, TIMESTAMP, INTEGER);
CREATE OR REPLACE FUNCTION hivemind_app.subscribe_to_post(
    _subscriber_id INTEGER,
    _author VARCHAR,
    _permlink VARCHAR,
    _block_num INTEGER,
    _block_date TIMESTAMP,
    _counter INTEGER
) RETURNS TABLE(success BOOLEAN, error_message TEXT) AS $$
DECLARE
    _post_id INTEGER;
    _already_subscribed BOOLEAN;
    _subscription_count INTEGER;
    _max_subscriptions CONSTANT INTEGER := 16;
    _error_msg TEXT;
BEGIN
    -- Combined query: find post + check subscription status + count subscriptions (3 queries -> 1)
    SELECT
        hp.id,
        EXISTS(SELECT 1 FROM hivemind_app.hive_post_subscriptions s WHERE s.account_id = _subscriber_id AND s.post_id = hp.id),
        (SELECT COUNT(*) FROM hivemind_app.hive_post_subscriptions s WHERE s.account_id = _subscriber_id)
    INTO _post_id, _already_subscribed, _subscription_count
    FROM hivemind_app.hive_posts hp
    JOIN hivemind_app.hive_accounts ha ON hp.author_id = ha.id
    JOIN hivemind_app.hive_permlink_data hpd ON hp.permlink_id = hpd.id
    WHERE ha.name = _author
      AND hpd.permlink = _permlink
      AND hp.counter_deleted = 0;

    IF _post_id IS NULL THEN
        RETURN QUERY SELECT FALSE, 'post not found'::TEXT;
        RETURN;
    END IF;

    IF _already_subscribed THEN
        RETURN QUERY SELECT FALSE, 'already subscribed'::TEXT;
        RETURN;
    END IF;

    IF _subscription_count >= _max_subscriptions THEN
        _error_msg := format('post subscription limit reached (max %s)', _max_subscriptions);

        -- Insert error notification to inform the user
        INSERT INTO hivemind_app.hive_notification_cache
        (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
        VALUES (
            hivemind_app.notification_id(_block_date, 10, _counter),
            _block_num,
            10,  -- error notification type
            _block_date,
            _subscriber_id,  -- src is the user who tried to subscribe
            _subscriber_id,  -- dst is also the user (notifying themselves)
            NULL,
            _post_id,
            35,
            _error_msg,
            '',
            ''
        )
        ON CONFLICT DO NOTHING;

        RETURN QUERY SELECT FALSE, _error_msg;
        RETURN;
    END IF;

    -- Insert subscription
    INSERT INTO hivemind_app.hive_post_subscriptions(account_id, post_id, created_at, block_num)
    VALUES (_subscriber_id, _post_id, _block_date, _block_num);

    RETURN QUERY SELECT TRUE, ''::TEXT;
END;
$$ LANGUAGE plpgsql;


-- Process subscribe_post custom_json ops from staging and generate notifications.
-- Called in Phase 6 of process_multi_sql / process_live_block_sql after posts are committed.
-- Ordering: INSERT subscribes → generate notifications → DELETE unsubscribes.
DROP FUNCTION IF EXISTS hivemind_app.process_subscriptions_from_staging(INT, INT);
CREATE OR REPLACE FUNCTION hivemind_app.process_subscriptions_from_staging(
    _first_block INT,
    _last_block INT
) RETURNS INT AS $$
DECLARE
    _subscribe_ops hivemind_app.post_subscription_op[];
    _unsubscribe_ops hivemind_app.post_unsubscription_op[];
    _unsub_sub_ids INTEGER[];
    _unsub_post_ids INTEGER[];
    _unsub_block_nums INTEGER[];
    _rec RECORD;
    _comment RECORD;
    _total_inserted INT := 0;
    _inserted INT;
    _inner_json JSONB;
    _action TEXT;
    _author TEXT;
    _permlink TEXT;
    _subscriber_name TEXT;
    _subscriber_id INT;
    _val JSONB;
    _last_counter_block INT := -1;
    _current_counter INT := 1;
    _notification_first_block INT;
BEGIN
    SELECT hivemind_app.block_before_irreversible('90 days') INTO _notification_first_block;
    IF _last_block <= _notification_first_block THEN
        RETURN 0;
    END IF;

    _subscribe_ops := ARRAY[]::hivemind_app.post_subscription_op[];
    _unsubscribe_ops := ARRAY[]::hivemind_app.post_unsubscription_op[];

    -- Parse subscribe_post custom_json ops from staging (op_type_id=18)
    FOR _rec IN
        SELECT s.block_num, s.block_date, s.val
        FROM hivemind_app._ops_staging s
        WHERE s.op_type_id = 18
          AND s.val->>'id' = 'subscribe_post'
        ORDER BY s.id
    LOOP
        _val := _rec.val;

        IF jsonb_array_length(COALESCE(_val->'required_auths', '[]'::jsonb)) != 0 THEN
            CONTINUE;
        END IF;
        IF jsonb_array_length(COALESCE(_val->'required_posting_auths', '[]'::jsonb)) != 1 THEN
            CONTINUE;
        END IF;
        _subscriber_name := _val->'required_posting_auths'->>0;

        BEGIN
            _inner_json := (_val->>'json')::jsonb;
        EXCEPTION WHEN OTHERS THEN
            CONTINUE;
        END;

        IF jsonb_typeof(_inner_json) != 'array' OR jsonb_array_length(_inner_json) != 2 THEN
            CONTINUE;
        END IF;

        _action := _inner_json->>0;
        IF _action NOT IN ('subscribe', 'unsubscribe') THEN
            CONTINUE;
        END IF;

        _author := _inner_json->1->>'author';
        _permlink := _inner_json->1->>'permlink';
        IF _author IS NULL OR _permlink IS NULL THEN
            CONTINUE;
        END IF;

        SELECT ha.id INTO _subscriber_id
        FROM hivemind_app.hive_accounts ha
        WHERE ha.name = _subscriber_name;

        IF NOT FOUND THEN
            CONTINUE;
        END IF;

        IF _action = 'subscribe' THEN
            _subscribe_ops := array_append(_subscribe_ops,
                ROW(_subscriber_id, _author, _permlink, _rec.block_num, _rec.block_date)::hivemind_app.post_subscription_op);
        ELSE
            _unsubscribe_ops := array_append(_unsubscribe_ops,
                ROW(_subscriber_id, _author, _permlink, _rec.block_num)::hivemind_app.post_unsubscription_op);
        END IF;
    END LOOP;

    -- INSERT subscribes so subscriptions exist before notification generation
    IF array_length(_subscribe_ops, 1) IS NOT NULL THEN
        PERFORM hivemind_app.flush_post_subscribes(_subscribe_ops);
    END IF;

    -- Resolve unsubscribe ops to (subscriber_id, post_id, block_num) arrays so that
    -- generate_post_subscription_notifications can exclude them without the rows being gone
    IF array_length(_unsubscribe_ops, 1) IS NOT NULL THEN
        SELECT
            array_agg(op.subscriber_id),
            array_agg(hp.id),
            array_agg(op.block_num)
        INTO _unsub_sub_ids, _unsub_post_ids, _unsub_block_nums
        FROM unnest(_unsubscribe_ops) op
        JOIN hivemind_app.hive_accounts ha ON ha.name = op.author
        JOIN hivemind_app.hive_permlink_data hpd ON hpd.permlink = op.permlink
        JOIN hivemind_app.hive_posts hp
            ON hp.author_id = ha.id AND hp.permlink_id = hpd.id AND hp.counter_deleted = 0;
    END IF;

    _unsub_sub_ids   := COALESCE(_unsub_sub_ids,   ARRAY[]::INTEGER[]);
    _unsub_post_ids  := COALESCE(_unsub_post_ids,  ARRAY[]::INTEGER[]);
    _unsub_block_nums := COALESCE(_unsub_block_nums, ARRAY[]::INTEGER[]);

    -- Generate notifications for every new comment in this batch.
    -- Read from _post_results (populated by Phase 3) instead of scanning hive_posts by block_num,
    -- because block_num_created has no index during MASSIVE_WITHOUT_INDEXES.
    FOR _comment IN
        SELECT pr.post_id, pr.author_id, pr.block_num, pr.block_date
        FROM hivemind_app._post_results pr
        WHERE pr.is_new_post = true
          AND pr.depth > 0
          AND pr.block_num > _notification_first_block
        ORDER BY pr.block_num, pr.post_id
    LOOP
        IF _comment.block_num != _last_counter_block THEN
            _last_counter_block := _comment.block_num;
            _current_counter := 1;
        END IF;

        SELECT hivemind_app.generate_post_subscription_notifications(
            _comment.post_id,
            _comment.author_id,
            _comment.block_num,
            _comment.block_date,
            _current_counter,
            _unsub_sub_ids,
            _unsub_post_ids,
            _unsub_block_nums
        ) INTO _inserted;

        _total_inserted  := _total_inserted  + COALESCE(_inserted, 0);
        _current_counter := _current_counter + COALESCE(_inserted, 0);
    END LOOP;

    -- DELETE unsubscribes AFTER notifications so subscriptions still exist during the query above
    IF array_length(_unsubscribe_ops, 1) IS NOT NULL THEN
        PERFORM hivemind_app.flush_post_unsubscribes(_unsubscribe_ops);
    END IF;

    RETURN _total_inserted;
END;
$$ LANGUAGE plpgsql;


DROP FUNCTION IF EXISTS hivemind_app.unsubscribe_from_post(INTEGER, VARCHAR, VARCHAR, INTEGER);
CREATE OR REPLACE FUNCTION hivemind_app.unsubscribe_from_post(
    _subscriber_id INTEGER,
    _author VARCHAR,
    _permlink VARCHAR,
    _block_num INTEGER
) RETURNS TABLE(success BOOLEAN, error_message TEXT) AS $$
DECLARE
    _post_id INTEGER;
    _is_subscribed BOOLEAN;
BEGIN
    -- Combined query: find post + check subscription status (2 queries -> 1)
    SELECT
        hp.id,
        EXISTS(SELECT 1 FROM hivemind_app.hive_post_subscriptions s WHERE s.account_id = _subscriber_id AND s.post_id = hp.id)
    INTO _post_id, _is_subscribed
    FROM hivemind_app.hive_posts hp
    JOIN hivemind_app.hive_accounts ha ON hp.author_id = ha.id
    JOIN hivemind_app.hive_permlink_data hpd ON hp.permlink_id = hpd.id
    WHERE ha.name = _author
      AND hpd.permlink = _permlink
      AND hp.counter_deleted = 0;

    IF _post_id IS NULL THEN
        RETURN QUERY SELECT FALSE, 'post not found'::TEXT;
        RETURN;
    END IF;

    IF NOT _is_subscribed THEN
        RETURN QUERY SELECT FALSE, 'not subscribed'::TEXT;
        RETURN;
    END IF;

    -- Delete subscription (notifications are preserved)
    DELETE FROM hivemind_app.hive_post_subscriptions
    WHERE account_id = _subscriber_id AND post_id = _post_id;

    RETURN QUERY SELECT TRUE, ''::TEXT;
END;
$$ LANGUAGE plpgsql;
