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
RETURNS SETOF bridge_api_community_context
LANGUAGE plpgsql
AS
$function$
DECLARE
    __account_id INT := find_account_id( _account, True );
    __community_id INT := find_community_id( _name, True );
    __subscribed BOOLEAN := EXISTS(SELECT 1 FROM hive_subscriptions WHERE account_id = __account_id AND community_id = __community_id);
BEGIN
    RETURN QUERY SELECT
        role_id,
        title,
        __subscribed
    FROM hive_roles
    WHERE account_id = __account_id
    AND community_id = __community_id
    LIMIT 1
    ;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 0::smallint, ''::VARCHAR, __subscribed::BOOLEAN;
    END IF;

END
$function$
;
