DROP FUNCTION IF EXISTS set_community_role_or_title;
CREATE OR REPLACE FUNCTION set_community_role_or_title(_community_id hive_posts.community_id%TYPE, _account_id hive_posts.author_id%TYPE, _role_id integer, _title varchar(140), _created_at timestamp)
RETURNS bool
LANGUAGE plpgsql
as
    $$
declare
        __subscription_id INTEGER;
        __role_id SMALLINT;
BEGIN
        SELECT id INTO __subscription_id FROM hive_subscriptions WHERE account_id = _account_id AND community_id = _community_id;

        if _role_id IS NOT NULL THEN
            SELECT role_id INTO __role_id FROM hive_roles WHERE account_id = _account_id AND community_id = _community_id;
            --raise '%aa', __subscription_id;
            -- We don't allow setting a higher role than the current one if you aren't subscribed
            IF __subscription_id IS NULL AND ((__role_id IS NOT NULL AND __role_id < _role_id ) OR __role_id IS NULL)  THEN
                return false;
            END IF;
        ELSE
            IF __subscription_id IS NULL THEN
                return false;
            END IF;
        end if;

        IF _role_id IS NOT NULL AND _title IS NULL THEN
            INSERT INTO hive_roles(account_id, community_id, role_id, created_at)
            VALUES (_account_id, _community_id, _role_id, _created_at)
            ON CONFLICT (account_id, community_id)
                DO UPDATE SET role_id = _role_id;
        ELSIF _title IS NOT NULL AND _role_id IS NULL THEN
            INSERT INTO hive_roles(account_id, community_id, title, created_at)
            VALUES (_account_id, _community_id, _title, _created_at)
            ON CONFLICT (account_id, community_id)
                DO UPDATE SET title = _title;
        END IF;

        RETURN TRUE;
END;
$$;