DROP TYPE IF EXISTS bridge_api_community_context CASCADE;
CREATE TYPE bridge_api_community_context AS (
    role_id SMALLINT,
    title VARCHAR,
    subscribed BOOLEAN
);

DROP FUNCTION IF EXISTS bridge_get_community_context
;
CREATE OR REPLACE FUNCTION bridge_get_community_context(
    in _account hive_accounts.name%TYPE,
    in _name hive_communities.name%TYPE
)
RETURNS SETOF JSON
LANGUAGE plpgsql
AS
$function$
DECLARE
    __account_id INT := find_account_id( _account, True );
    __community_id INT := find_community_id( _name, True );
    __subscribed BOOLEAN;
BEGIN

    IF __account_id = 0 THEN
      RETURN QUERY SELECT '{}'::json;
      RETURN;
    END IF;

    __subscribed = EXISTS(SELECT 1 FROM hive_subscriptions WHERE account_id = __account_id AND community_id = __community_id);

    RETURN QUERY SELECT
        json_build_object(
            'role', get_role_name(role_id),
            'subscribed', __subscribed,
            'title', title
        )
    FROM hive_roles
    WHERE account_id = __account_id
    AND community_id = __community_id
    ;

    IF NOT FOUND THEN
        RETURN QUERY SELECT json_build_object(
            'role', get_role_name(0),
            'subscribed', __subscribed,
            'title', ''
        );
    END IF;

END
$function$
;
