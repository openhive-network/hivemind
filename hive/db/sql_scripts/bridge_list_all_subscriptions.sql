DROP TYPE IF EXISTS bridge_api_list_all_subscriptions CASCADE;
CREATE TYPE bridge_api_list_all_subscriptions AS (
    name VARCHAR,
    title VARCHAR,
    role_id SMALLINT,
    role_title VARCHAR
);

DROP FUNCTION IF EXISTS bridge_list_all_subscriptions
;
CREATE OR REPLACE FUNCTION bridge_list_all_subscriptions(
    in _account hive_accounts.name%TYPE
)
RETURNS SETOF bridge_api_list_all_subscriptions
LANGUAGE plpgsql
AS
$function$
DECLARE
    __account_id INT := find_account_id( _account, True );
BEGIN

    RETURN QUERY
    SELECT c.name, c.title, COALESCE(r.role_id, 0)::SMALLINT, COALESCE(r.title, '')
    FROM hive_communities c
    JOIN hive_subscriptions s ON c.id = s.community_id
    LEFT JOIN hive_roles r ON r.account_id = s.account_id
        AND r.community_id = c.id
    WHERE s.account_id = __account_id
    ORDER BY COALESCE(role_id, 0) DESC, c.rank;
END
$function$
;