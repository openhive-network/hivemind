DROP FUNCTION IF EXISTS hivemind_app.community_is_subscribed;
CREATE OR REPLACE FUNCTION hivemind_app.community_is_subscribed(
    _account_id INTEGER,
    _community_id INTEGER
) RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS(
        SELECT 1 FROM hivemind_app.hive_subscriptions
        WHERE community_id = _community_id
          AND account_id = _account_id
    );
END;
$$ LANGUAGE plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.get_community_role;
CREATE OR REPLACE FUNCTION hivemind_app.get_community_role(
    _account_id INTEGER,
    _community_id INTEGER
) RETURNS INTEGER AS $$
BEGIN
    -- default to guest = 0 if no role
    RETURN COALESCE(
        (SELECT role_id FROM hivemind_app.hive_roles
         WHERE community_id = _community_id AND account_id = _account_id),
        0
    );
END;
$$ LANGUAGE plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.get_post_id_by_permlink;
CREATE OR REPLACE FUNCTION hivemind_app.get_post_id_by_permlink(
    _account_id INTEGER,
    _permlink VARCHAR,
    _community_id INTEGER
) RETURNS TABLE(post_id INTEGER, error_message TEXT) AS $$
DECLARE
    _post_id INTEGER;
    _post_community_id INTEGER;
BEGIN
    SELECT hp.id, hp.community_id INTO _post_id, _post_community_id
    FROM hivemind_app.live_posts_comments_view hp
    JOIN hivemind_app.hive_permlink_data hpd ON hp.permlink_id = hpd.id
    WHERE hp.author_id = _account_id AND hpd.permlink = _permlink;

    IF _post_id IS NULL THEN
        RETURN QUERY SELECT NULL::INTEGER, 'post does not exist'::TEXT;
        RETURN;
    END IF;

    IF _post_community_id != _community_id THEN
        RETURN QUERY SELECT NULL::INTEGER, 'post does not belong to community'::TEXT;
        RETURN;
    END IF;

    RETURN QUERY SELECT _post_id, ''::TEXT;
END;
$$ LANGUAGE plpgsql STABLE;
