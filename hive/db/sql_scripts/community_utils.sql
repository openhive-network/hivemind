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
    -- Get account's role in the community (default to guest = 0 if no role)
    RETURN COALESCE(
        (SELECT role_id FROM hivemind_app.hive_roles
         WHERE community_id = _community_id AND account_id = _account_id),
        0
    );
END;
$$ LANGUAGE plpgsql STABLE;
