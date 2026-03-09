-- Post subscription notification generation
-- Called when a new comment is created to notify all subscribers of ancestor posts

DROP FUNCTION IF EXISTS hivemind_app.generate_post_subscription_notifications(INTEGER, INTEGER, INTEGER, TIMESTAMP, INTEGER);
DROP FUNCTION IF EXISTS hivemind_app.generate_post_subscription_notifications(INTEGER, INTEGER, INTEGER, TIMESTAMP, INTEGER, INTEGER[], INTEGER[], INTEGER[]);
CREATE OR REPLACE FUNCTION hivemind_app.generate_post_subscription_notifications(
    _new_post_id INTEGER,
    _author_id INTEGER,
    _block_num INTEGER,
    _block_date TIMESTAMP,
    _counter INTEGER,
    _unsub_subscriber_ids INTEGER[] DEFAULT ARRAY[]::INTEGER[],
    _unsub_post_ids INTEGER[] DEFAULT ARRAY[]::INTEGER[],
    _unsub_block_nums INTEGER[] DEFAULT ARRAY[]::INTEGER[]
) RETURNS INTEGER AS $$
DECLARE
    _notification_first_block INTEGER;
    _parent_post_id INTEGER;
    _inserted_count INTEGER;
BEGIN
    -- Check if we're within the notification window
    SELECT hivemind_app.block_before_irreversible('90 days') INTO _notification_first_block;
    IF _block_num <= _notification_first_block THEN
        RETURN 0;
    END IF;

    -- Get the parent_id of the new post
    SELECT parent_id INTO _parent_post_id
    FROM hivemind_app.hive_posts
    WHERE id = _new_post_id;

    -- If no parent (root post) or parent is 0, no ancestors to notify
    IF _parent_post_id IS NULL OR _parent_post_id = 0 THEN
        RETURN 0;
    END IF;



    -- Use recursive CTE to walk up the parent chain and find all subscribers
    -- Then insert notifications for each subscriber (except the comment author)
    WITH RECURSIVE ancestors AS (
        -- Start with the immediate parent
        SELECT p.id, p.parent_id, 1 as depth
        FROM hivemind_app.hive_posts p
        WHERE p.id = _parent_post_id
          AND p.id != 0

        UNION ALL

        -- Walk up to each ancestor
        SELECT p.id, p.parent_id, a.depth + 1
        FROM hivemind_app.hive_posts p
        JOIN ancestors a ON p.id = a.parent_id
        WHERE p.id != 0 AND a.depth < 16  -- Limit depth to 16 for performance optimization
    ),
    -- Get all unique subscribers of ancestor posts (excluding comment author)
    -- Only include subscribers who subscribed BEFORE this comment was created
    subscribers AS (
        SELECT DISTINCT s.account_id
        FROM hivemind_app.hive_post_subscriptions s
        JOIN ancestors a ON s.post_id = a.id
        WHERE s.account_id != _author_id  -- Don't notify comment author
          AND s.block_num < _block_num    -- Only notify if subscribed before this comment
          AND NOT EXISTS (                -- Exclude subscribers with pending unsubscribes
              SELECT 1
              FROM unnest(_unsub_subscriber_ids, _unsub_post_ids, _unsub_block_nums) AS u(sid, pid, bnum)
              WHERE u.sid = s.account_id
                AND u.pid = a.id
                AND u.bnum <= _block_num
          )
    ),
    -- Get reputation scores for subscribers ONLY (not entire table)
    subscriber_haf_ids AS (
        SELECT ha.haf_id
        FROM subscribers s
        JOIN hivemind_app.hive_accounts ha ON s.account_id = ha.id
    ),
    log_account_rep AS (
        SELECT
            ar.account_id,
            LOG(10, ABS(NULLIF(ar.reputation, 0))) AS rep,
            (CASE WHEN ar.reputation < 0 THEN -1 ELSE 1 END) AS is_neg
        FROM reptracker_app.account_reputations ar
        WHERE ar.account_id IN (SELECT haf_id FROM subscriber_haf_ids)
    ),
    calculate_rep AS (
        SELECT
            account_id,
            GREATEST(lar.rep - 9, 0) * lar.is_neg AS rep
        FROM log_account_rep lar
    ),
    final_rep AS (
        SELECT account_id, (cr.rep * 7.5 + 25)::INT AS rep FROM calculate_rep AS cr
    ),
    inserted AS (
        INSERT INTO hivemind_app.hive_notification_cache
        (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
        SELECT
            hivemind_app.notification_id(_block_date, 18, (_counter + ROW_NUMBER() OVER (ORDER BY s.account_id) - 1)::INTEGER),
            _block_num,
            18,  -- post_subscription_reply notification type
            _block_date,
            _author_id,  -- src is the comment author
            s.account_id,  -- dst is the subscriber
            _parent_post_id,  -- dst_post_id is the immediate parent (where reply was made to)
            _new_post_id,  -- post_id is the new comment
            COALESCE(r.rep, 25),
            '',
            '',
            ''
        FROM subscribers s
        JOIN hivemind_app.hive_accounts ha ON s.account_id = ha.id
        LEFT JOIN final_rep r ON ha.haf_id = r.account_id
        -- Exclude muted relationships
        LEFT JOIN hivemind_app.muted m ON m.follower = s.account_id AND m.following = _author_id
        LEFT JOIN hivemind_app.follow_muted fm ON fm.follower = s.account_id
        LEFT JOIN hivemind_app.muted mi ON mi.follower = fm.following AND mi.following = _author_id
        WHERE COALESCE(r.rep, 25) > 0
          AND m.follower IS NULL
          AND mi.following IS NULL
        ON CONFLICT DO NOTHING
        RETURNING 1
    )
    SELECT COUNT(*) INTO _inserted_count FROM inserted;

    RETURN _inserted_count;
END;
$$ LANGUAGE plpgsql;
