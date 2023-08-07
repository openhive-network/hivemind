DROP FUNCTION IF EXISTS hivemind_app.validate_community_set_role;
CREATE OR REPLACE FUNCTION hivemind_app.validate_community_set_role(_community_id hivemind_app.hive_posts.community_id%TYPE, _account_id hivemind_app.hive_posts.author_id%TYPE, _role_id integer)
RETURNS bool
LANGUAGE plpgsql
as
    $$
declare
        __subscription_id INTEGER;
        __role_id SMALLINT;
BEGIN
        SELECT id INTO __subscription_id FROM hivemind_app.hive_subscriptions WHERE account_id = _account_id AND community_id = _community_id;
        IF _role_id IS NOT NULL THEN
            -- We allow setting the MUTED role even if you're not subscribed
            IF _role_id > 0 THEN
                SELECT role_id INTO __role_id FROM hivemind_app.hive_roles WHERE account_id = _account_id AND community_id = _community_id;
                -- We don't allow setting a higher role than the current one if you aren't subscribed
                IF __subscription_id IS NULL AND ((__role_id IS NOT NULL AND __role_id < _role_id ) OR __role_id IS NULL)  THEN
                    return false;
                END IF;
            END IF;
        ELSE
            IF __subscription_id IS NULL THEN
                return false;
            END IF;
        end if;

        RETURN TRUE;
END;
$$;
