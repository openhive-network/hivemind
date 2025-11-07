-- Create sequence for notification counter if it doesn't exist
CREATE SEQUENCE IF NOT EXISTS hivemind_app.notification_counter_seq;

DROP FUNCTION IF EXISTS hivemind_app.insert_subscription;
CREATE OR REPLACE FUNCTION hivemind_app.community_subscribe(
    _actor_id INTEGER,
    _community_id INTEGER,
    _date TIMESTAMP,
    _block_num INTEGER
) RETURNS VOID AS $$
DECLARE
    _counter INTEGER;
    _notification_first_block INTEGER;
BEGIN
    -- Insert subscription
    INSERT INTO hivemind_app.hive_subscriptions
    (account_id, community_id, created_at, block_num)
    VALUES (_actor_id, _community_id, _date, _block_num);

    -- Update community subscriber count
    UPDATE hivemind_app.hive_communities
    SET subscribers = subscribers + 1
    WHERE id = _community_id;

    -- Create notification if block is recent enough
    SELECT hivemind_app.block_before_irreversible('90 days') INTO _notification_first_block;

    IF _block_num > _notification_first_block THEN
        -- Get next counter value
        _counter := nextval('hivemind_app.notification_counter_seq')::INTEGER % 4194303;

        -- Insert notification with reputation calculation
        WITH log_account_rep AS (
            SELECT
                account_id,
                LOG(10, ABS(NULLIF(reputation, 0))) AS rep,
                (CASE WHEN reputation < 0 THEN -1 ELSE 1 END) AS is_neg
            FROM reptracker_app.account_reputations
        ),
        calculate_rep AS (
            SELECT
                account_id,
                GREATEST(lar.rep - 9, 0) * lar.is_neg AS rep
            FROM log_account_rep lar
        ),
        final_rep AS (
            SELECT account_id, (cr.rep * 7.5 + 25)::INT AS rep FROM calculate_rep AS cr
        )
        INSERT INTO hivemind_app.hive_notification_cache
        (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
        SELECT
            hivemind_app.notification_id(_date, 11, _counter),
            _block_num,
            11,
            _date,
            r.id,
            hc.id,
            0,
            0,
            COALESCE(rep.rep, 25),
            '',
            hc.name,
            hc.title
        FROM hivemind_app.hive_accounts AS r
        JOIN hivemind_app.hive_communities AS hc ON hc.id = _community_id
        LEFT JOIN final_rep AS rep ON r.haf_id = rep.account_id
        WHERE r.id = _actor_id
            AND _block_num > hivemind_app.block_before_irreversible('90 days')
            AND COALESCE(rep.rep, 25) > 0
            AND r.id IS DISTINCT FROM hc.id
        ON CONFLICT (src, dst, type_id, post_id, block_num) DO NOTHING;
    END IF;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS hivemind_app.set_community_role;
CREATE OR REPLACE FUNCTION hivemind_app.set_community_role(
    _account_id INTEGER,
    _community_id INTEGER,
    _role_id INTEGER,
    _date TIMESTAMP,
    _max_mod_nb INTEGER, -- maximum number of roles >= to mod in a community
    _mod_role_threshold INTEGER -- minimum role id to be counted as
) RETURNS TABLE(status TEXT, mod_count BIGINT) AS $$
BEGIN
    RETURN QUERY
    WITH mod_check AS (
        SELECT
            CASE
                WHEN _role_id >= _mod_role_threshold THEN
                    (SELECT COUNT(*)
                     FROM hivemind_app.hive_roles
                     WHERE community_id = _community_id
                     AND role_id >= _mod_role_threshold
                         AND account_id != _account_id)
                ELSE 0
            END as current_mod_count
    ),
    insert_attempt AS (
        INSERT INTO hivemind_app.hive_roles (account_id, community_id, role_id, created_at)
        SELECT _account_id, _community_id, _role_id, _date
        FROM mod_check
        WHERE current_mod_count < _max_mod_nb OR _role_id < _mod_role_threshold
        ON CONFLICT (account_id, community_id)
        DO UPDATE SET role_id = _role_id
        RETURNING *
    )
    SELECT
        CASE
            WHEN EXISTS (SELECT 1 FROM insert_attempt) THEN 'success'
            ELSE 'failed_mod_limit'
        END as status,
        (SELECT current_mod_count FROM mod_check) as mod_count;
END;
$$ LANGUAGE plpgsql;