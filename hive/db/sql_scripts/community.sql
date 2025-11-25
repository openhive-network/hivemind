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
            NULL,
            NULL,
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
            NULL,
            NULL,
            35,
            '',
            _name,
            ''
        WHERE _block_num > hivemind_app.block_before_irreversible('90 days');
    END IF;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS hivemind_app.community_set_user_title;
CREATE OR REPLACE FUNCTION hivemind_app.community_set_user_title(
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

DROP FUNCTION IF EXISTS hivemind_app.community_mute_post;
CREATE OR REPLACE FUNCTION hivemind_app.community_mute_post(
    _actor_id INTEGER,
    _community_id INTEGER,
    _account_id INTEGER,
    _permlink VARCHAR,
    _muted_reasons INTEGER
) RETURNS TABLE(success BOOLEAN, error_message TEXT, post_id INTEGER, is_subscribed BOOLEAN) AS $$
DECLARE
    _actor_role INTEGER;
    _is_muted BOOLEAN;
    _post_id INTEGER;
    _post_error TEXT;
    _is_subscribed BOOLEAN;
BEGIN
    _actor_role := hivemind_app.get_community_role(_actor_id, _community_id);

    IF _actor_role < 4 THEN
        RETURN QUERY SELECT FALSE, 'only mods and above can mute posts'::TEXT, NULL::INTEGER, FALSE;
        RETURN;
    END IF;

    SELECT p.post_id, p.error_message INTO _post_id, _post_error
    FROM hivemind_app.get_post_id_by_permlink(_account_id, _permlink, _community_id) p;

    IF _post_id IS NULL THEN
        RETURN QUERY SELECT FALSE, _post_error, NULL::INTEGER, FALSE;
        RETURN;
    END IF;

    SELECT is_muted INTO _is_muted FROM hivemind_app.hive_posts WHERE id = _post_id;

    IF _is_muted THEN
        RETURN QUERY SELECT FALSE, 'post is already muted'::TEXT, NULL::INTEGER, FALSE;
        RETURN;
    END IF;

    UPDATE hivemind_app.hive_posts
    SET is_muted = true, muted_reasons = _muted_reasons
    WHERE id = _post_id;

    _is_subscribed := hivemind_app.community_is_subscribed(_account_id, _community_id);

    RETURN QUERY SELECT TRUE, ''::TEXT, _post_id, _is_subscribed;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS hivemind_app.community_unmute_post;
CREATE OR REPLACE FUNCTION hivemind_app.community_unmute_post(
    _actor_id INTEGER,
    _community_id INTEGER,
    _account_id INTEGER,
    _permlink VARCHAR
) RETURNS TABLE(success BOOLEAN, error_message TEXT, post_id INTEGER, is_subscribed BOOLEAN) AS $$
DECLARE
    _actor_role INTEGER;
    _is_muted BOOLEAN;
    _parent_id INTEGER;
    _parent_is_muted BOOLEAN;
    _post_id INTEGER;
    _post_error TEXT;
    _is_subscribed BOOLEAN;
BEGIN
    _actor_role := hivemind_app.get_community_role(_actor_id, _community_id);

    IF _actor_role < 4 THEN
        RETURN QUERY SELECT FALSE, 'only mods and above can unmute posts'::TEXT, NULL::INTEGER, FALSE;
        RETURN;
    END IF;

    SELECT p.post_id, p.error_message INTO _post_id, _post_error
    FROM hivemind_app.get_post_id_by_permlink(_account_id, _permlink, _community_id) p;

    IF _post_id IS NULL THEN
        RETURN QUERY SELECT FALSE, _post_error, NULL::INTEGER, FALSE;
        RETURN;
    END IF;

    SELECT is_muted, parent_id INTO _is_muted, _parent_id FROM hivemind_app.hive_posts WHERE id = _post_id;

    IF NOT _is_muted THEN
        RETURN QUERY SELECT FALSE, 'post is not muted'::TEXT, NULL::INTEGER, FALSE;
        RETURN;
    END IF;

    IF _parent_id IS NOT NULL THEN
        SELECT is_muted INTO _parent_is_muted FROM hivemind_app.hive_posts WHERE id = _parent_id;
        IF _parent_is_muted THEN
            RETURN QUERY SELECT FALSE, 'parent post is muted'::TEXT, NULL::INTEGER, FALSE;
            RETURN;
        END IF;
    END IF;

    UPDATE hivemind_app.hive_posts
    SET is_muted = false, muted_reasons = 0
    WHERE id = _post_id;

    _is_subscribed := hivemind_app.community_is_subscribed(_account_id, _community_id);

    RETURN QUERY SELECT TRUE, ''::TEXT, _post_id, _is_subscribed;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS hivemind_app.community_pin_post;
CREATE OR REPLACE FUNCTION hivemind_app.community_pin_post(
    _actor_id INTEGER,
    _community_id INTEGER,
    _account_id INTEGER,
    _permlink VARCHAR
) RETURNS TABLE(success BOOLEAN, error_message TEXT, post_id INTEGER, is_subscribed BOOLEAN) AS $$
DECLARE
    _actor_role INTEGER;
    _is_pinned BOOLEAN;
    _post_id INTEGER;
    _post_error TEXT;
    _is_subscribed BOOLEAN;
BEGIN
    _actor_role := hivemind_app.get_community_role(_actor_id, _community_id);

    IF _actor_role < 4 THEN
        RETURN QUERY SELECT FALSE, 'only mods and above can pin posts'::TEXT, NULL::INTEGER, FALSE;
        RETURN;
    END IF;

    SELECT p.post_id, p.error_message INTO _post_id, _post_error
    FROM hivemind_app.get_post_id_by_permlink(_account_id, _permlink, _community_id) p;

    IF _post_id IS NULL THEN
        RETURN QUERY SELECT FALSE, _post_error, NULL::INTEGER, FALSE;
        RETURN;
    END IF;

    SELECT is_pinned INTO _is_pinned FROM hivemind_app.hive_posts WHERE id = _post_id;

    IF _is_pinned THEN
        RETURN QUERY SELECT FALSE, 'post is already pinned'::TEXT, NULL::INTEGER, FALSE;
        RETURN;
    END IF;

    UPDATE hivemind_app.hive_posts
    SET is_pinned = true
    WHERE id = _post_id;

    _is_subscribed := hivemind_app.community_is_subscribed(_account_id, _community_id);

    RETURN QUERY SELECT TRUE, ''::TEXT, _post_id, _is_subscribed;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS hivemind_app.community_unpin_post;
CREATE OR REPLACE FUNCTION hivemind_app.community_unpin_post(
    _actor_id INTEGER,
    _community_id INTEGER,
    _account_id INTEGER,
    _permlink VARCHAR
) RETURNS TABLE(success BOOLEAN, error_message TEXT, post_id INTEGER, is_subscribed BOOLEAN) AS $$
DECLARE
    _actor_role INTEGER;
    _is_pinned BOOLEAN;
    _post_id INTEGER;
    _post_error TEXT;
    _is_subscribed BOOLEAN;
BEGIN
    _actor_role := hivemind_app.get_community_role(_actor_id, _community_id);

    IF _actor_role < 4 THEN
        RETURN QUERY SELECT FALSE, 'only mods and above can unpin posts'::TEXT, NULL::INTEGER, FALSE;
        RETURN;
    END IF;

    SELECT p.post_id, p.error_message INTO _post_id, _post_error
    FROM hivemind_app.get_post_id_by_permlink(_account_id, _permlink, _community_id) p;

    IF _post_id IS NULL THEN
        RETURN QUERY SELECT FALSE, _post_error, NULL::INTEGER, FALSE;
        RETURN;
    END IF;

    SELECT is_pinned INTO _is_pinned FROM hivemind_app.hive_posts WHERE id = _post_id;

    IF NOT _is_pinned THEN
        RETURN QUERY SELECT FALSE, 'post is not pinned'::TEXT, NULL::INTEGER, FALSE;
        RETURN;
    END IF;

    UPDATE hivemind_app.hive_posts
    SET is_pinned = false
    WHERE id = _post_id;

    _is_subscribed := hivemind_app.community_is_subscribed(_account_id, _community_id);

    RETURN QUERY SELECT TRUE, ''::TEXT, _post_id, _is_subscribed;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS hivemind_app.community_flag_post;
CREATE OR REPLACE FUNCTION hivemind_app.community_flag_post(
    _actor_id INTEGER,
    _community_id INTEGER,
    _account_id INTEGER,
    _permlink VARCHAR,
    _community_name VARCHAR
) RETURNS TABLE(success BOOLEAN, error_message TEXT, post_id INTEGER, team_members INTEGER[], is_subscribed BOOLEAN) AS $$
DECLARE
    _actor_role INTEGER;
    _already_flagged BOOLEAN;
    _team_members INTEGER[];
    _post_id INTEGER;
    _post_error TEXT;
    _is_subscribed BOOLEAN;
BEGIN
    _actor_role := hivemind_app.get_community_role(_actor_id, _community_id);

    IF _actor_role <= -2 THEN
        RETURN QUERY SELECT FALSE, 'muted users cannot flag posts'::TEXT, NULL::INTEGER, NULL::INTEGER[], FALSE;
        RETURN;
    END IF;

    SELECT p.post_id, p.error_message INTO _post_id, _post_error
    FROM hivemind_app.get_post_id_by_permlink(_account_id, _permlink, _community_id) p;

    IF _post_id IS NULL THEN
        RETURN QUERY SELECT FALSE, _post_error, NULL::INTEGER, NULL::INTEGER[], FALSE;
        RETURN;
    END IF;

    SELECT EXISTS(
        SELECT 1 FROM hivemind_app.hive_notification_cache
        WHERE community = _community_name
          AND hive_notification_cache.post_id = _post_id
          AND type_id = 9 -- flag_post
          AND src = _actor_id
    ) INTO _already_flagged;

    IF _already_flagged THEN
        RETURN QUERY SELECT FALSE, 'user already flagged this post'::TEXT, NULL::INTEGER, NULL::INTEGER[], FALSE;
        RETURN;
    END IF;

    SELECT ARRAY_AGG(account_id) INTO _team_members
    FROM hivemind_app.hive_roles
    WHERE community_id = _community_id
      AND role_id >= 4; -- better or equal to mod

    _is_subscribed := hivemind_app.community_is_subscribed(_account_id, _community_id);

    RETURN QUERY SELECT TRUE, ''::TEXT, _post_id, _team_members, _is_subscribed;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS hivemind_app.update_community_props;
CREATE OR REPLACE FUNCTION hivemind_app.update_community_props(
    _actor_id INTEGER,
    _community_id INTEGER,
    _props JSONB
) RETURNS TABLE(success BOOLEAN, error_message TEXT, team_members INTEGER[]) AS $$
DECLARE
    _actor_role INTEGER;
    _team_members INTEGER[];
BEGIN
    _actor_role := hivemind_app.get_community_role(_actor_id, _community_id);

    IF _actor_role < 6 THEN
        RETURN QUERY SELECT FALSE, 'only admins can update props'::TEXT, NULL::INTEGER[];
        RETURN;
    END IF;

    UPDATE hivemind_app.hive_communities
    SET
        title = CASE WHEN jsonb_exists(_props, 'title') THEN _props->>'title' ELSE title END,
        about = CASE WHEN jsonb_exists(_props, 'about') THEN _props->>'about' ELSE about END,
        lang = CASE WHEN jsonb_exists(_props, 'lang') THEN _props->>'lang' ELSE lang END,
        is_nsfw = CASE WHEN jsonb_exists(_props, 'is_nsfw') THEN (_props->>'is_nsfw')::BOOLEAN ELSE is_nsfw END,
        description = CASE WHEN jsonb_exists(_props, 'description') THEN _props->>'description' ELSE description END,
        flag_text = CASE WHEN jsonb_exists(_props, 'flag_text') THEN _props->>'flag_text' ELSE flag_text END,
        settings = CASE WHEN jsonb_exists(_props, 'settings') THEN (_props->>'settings')::JSONB ELSE settings END,
        type_id = CASE WHEN jsonb_exists(_props, 'type_id') THEN (_props->>'type_id')::INTEGER ELSE type_id END
    WHERE id = _community_id;

    SELECT ARRAY_AGG(account_id) INTO _team_members
    FROM hivemind_app.hive_roles
    WHERE community_id = _community_id
      AND role_id >= 4; --  better or equal to mod

    RETURN QUERY SELECT TRUE, ''::TEXT, _team_members;
END;
$$ LANGUAGE plpgsql;