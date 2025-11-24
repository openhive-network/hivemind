DROP FUNCTION IF EXISTS hivemind_app.community_subscribe(INTEGER, INTEGER, TIMESTAMP, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION hivemind_app.community_subscribe(
    _actor_id INTEGER,
    _community_id INTEGER,
    _date TIMESTAMP,
    _block_num INTEGER,
    _counter INTEGER
) RETURNS TABLE(success BOOLEAN, error_message TEXT) AS $$
DECLARE
    _notification_first_block INTEGER;
    _already_subscribed BOOLEAN;
BEGIN
    _already_subscribed := hivemind_app.community_is_subscribed(_actor_id, _community_id);

    IF _already_subscribed THEN
        RETURN QUERY SELECT FALSE, 'already subscribed'::TEXT;
        RETURN;
    END IF;

    INSERT INTO hivemind_app.hive_subscriptions(account_id, community_id, created_at, block_num) VALUES (_actor_id, _community_id, _date, _block_num);

    UPDATE hivemind_app.hive_communities SET subscribers = subscribers + 1 WHERE id = _community_id;

    -- With clause is inlined, modified call to reptracker_endpoints.get_account_reputation.
    -- Reputation is multiplied by 7.5 rather than 9 to bring the max value to 100 rather than 115.
    -- In case of reputation being 0, the score is set to 25 rather than 0.
    SELECT hivemind_app.block_before_irreversible('90 days') INTO _notification_first_block;
    IF _block_num > _notification_first_block THEN
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

    RETURN QUERY SELECT TRUE, ''::TEXT;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS hivemind_app.community_unsubscribe(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION hivemind_app.community_unsubscribe(
    _actor_id INTEGER,
    _community_id INTEGER
) RETURNS TABLE(success BOOLEAN, error_message TEXT) AS $$
DECLARE
    _is_subscribed BOOLEAN;
BEGIN
    _is_subscribed := hivemind_app.community_is_subscribed(_actor_id, _community_id);

    IF NOT _is_subscribed THEN
        RETURN QUERY SELECT FALSE, 'already unsubscribed'::TEXT;
        RETURN;
    END IF;

    DELETE FROM hivemind_app.hive_subscriptions WHERE account_id = _actor_id AND community_id = _community_id;

    UPDATE hivemind_app.hive_communities SET subscribers = subscribers - 1 WHERE id = _community_id;

    RETURN QUERY SELECT TRUE, ''::TEXT;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS hivemind_app.set_community_role;
CREATE OR REPLACE FUNCTION hivemind_app.set_community_role(
    _actor_id INTEGER,
    _account_id INTEGER,
    _community_id INTEGER,
    _role_id INTEGER,
    _date TIMESTAMP,
    _max_mod_nb INTEGER, -- maximum number of roles >= to mod in a community
    _mod_role_threshold INTEGER -- minimum role id to be counted as
) RETURNS TABLE(success BOOLEAN, error_message TEXT) AS $$
DECLARE
    _actor_role INTEGER;
    _account_role INTEGER;
    _mod_count BIGINT;
BEGIN
    _actor_role := hivemind_app.get_community_role(_actor_id, _community_id);

    IF _actor_role < 4 THEN  -- 4 = Role.mod
        RETURN QUERY SELECT FALSE, 'only mods and up can alter roles'::TEXT;
        RETURN;
    END IF;

    IF _actor_role <= _role_id THEN
        RETURN QUERY SELECT FALSE, 'cannot promote to or above own rank'::TEXT;
        RETURN;
    END IF;

    _account_role := hivemind_app.get_community_role(_account_id, _community_id);

    IF _account_role = 8 THEN  -- 8 = Role.owner
        RETURN QUERY SELECT FALSE, 'cant modify owner role'::TEXT;
        RETURN;
    END IF;


    IF _actor_id != _account_id THEN
        IF _account_role >= _actor_role THEN
            RETURN QUERY SELECT FALSE, 'cant modify a user with a higher role'::TEXT;
            RETURN;
        END IF;

        IF _account_role = _role_id THEN
            RETURN QUERY SELECT FALSE, 'role would not change'::TEXT;
            RETURN;
        END IF;
    END IF;

    -- Check mod limit if promoting to mod or above
    IF _role_id >= _mod_role_threshold THEN
        SELECT COUNT(*) INTO _mod_count
        FROM hivemind_app.hive_roles
        WHERE community_id = _community_id
          AND role_id >= _mod_role_threshold
          AND account_id != _account_id;

        IF _mod_count >= _max_mod_nb THEN
            RETURN QUERY SELECT FALSE, 'moderator limit exceeded'::TEXT;
            RETURN;
        END IF;
    END IF;

    INSERT INTO hivemind_app.hive_roles (account_id, community_id, role_id, created_at)
    VALUES (_account_id, _community_id, _role_id, _date)
    ON CONFLICT (account_id, community_id)
    DO UPDATE SET role_id = _role_id;

    RETURN QUERY SELECT TRUE, ''::TEXT;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS hivemind_app.register_community;
CREATE OR REPLACE FUNCTION hivemind_app.register_community(
    _name VARCHAR,
    _account_id INTEGER,
    _block_date TIMESTAMP,
    _block_num INTEGER,
    _counter INTEGER
) RETURNS VOID AS $$
DECLARE
    _type_id INTEGER;
    _notification_first_block INTEGER;
BEGIN
    -- Extract type_id from name (6th character, after "hive-")
    _type_id := SUBSTRING(_name, 6, 1)::INTEGER;

    INSERT INTO hivemind_app.hive_communities (id, name, type_id, created_at, block_num)
    VALUES (_account_id, _name, _type_id, _block_date, _block_num);

    INSERT INTO hivemind_app.hive_roles (community_id, account_id, role_id, created_at)
    VALUES (_account_id, _account_id, 8, _block_date); -- 8 = owner role id

    SELECT hivemind_app.block_before_irreversible('90 days') INTO _notification_first_block;
    IF _block_num > _notification_first_block THEN
        INSERT INTO hivemind_app.hive_notification_cache
        (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
        SELECT
            hivemind_app.notification_id(_block_date, 1, _counter),
            _block_num,
            1,
            _block_date,
            0,
            _account_id,
            0,
            0,
            35,
            '',
            _name,
            ''
        WHERE _block_num > hivemind_app.block_before_irreversible('90 days');
    END IF;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS hivemind_app.set_user_title;
CREATE OR REPLACE FUNCTION hivemind_app.set_user_title(
    _actor_id INTEGER,
    _account_id INTEGER,
    _community_id INTEGER,
    _title VARCHAR,
    _date TIMESTAMP
) RETURNS TABLE(success BOOLEAN, error_message TEXT) AS $$
DECLARE
    _actor_role INTEGER;
    _community_name VARCHAR;
    _community_title VARCHAR;
BEGIN
    _actor_role := hivemind_app.get_community_role(_actor_id, _community_id);

    -- 4 is mod
    IF _actor_role < 4 THEN
        RETURN QUERY SELECT FALSE, 'only mods can set user titles'::TEXT;
        RETURN;
    END IF;

    INSERT INTO hivemind_app.hive_roles (account_id, community_id, title, created_at)
    VALUES (_account_id, _community_id, _title, _date)
    ON CONFLICT (account_id, community_id)
    DO UPDATE SET title = _title;

    RETURN QUERY SELECT TRUE, ''::TEXT;
END;
$$ LANGUAGE plpgsql;