DROP TYPE IF EXISTS hivemind_app.bridge_api_list_all_subscriptions CASCADE;
CREATE TYPE hivemind_app.bridge_api_list_all_subscriptions AS (
    name VARCHAR,
    title VARCHAR,
    role VARCHAR,
    role_title VARCHAR
);

DROP FUNCTION IF EXISTS hivemind_app.bridge_list_all_subscriptions
;
CREATE OR REPLACE FUNCTION hivemind_app.bridge_list_all_subscriptions(
    in _account hivemind_app.hive_accounts.name%TYPE
)
RETURNS SETOF hivemind_app.bridge_api_list_all_subscriptions
LANGUAGE plpgsql
AS
$function$
DECLARE
    __account_id INT := hivemind_app.find_account_id( _account, True );
BEGIN

    RETURN QUERY
    SELECT c.name, c.title, hivemind_app.get_role_name(COALESCE(r.role_id, 0)), COALESCE(r.title, '')
    FROM hivemind_app.hive_communities c
    JOIN hivemind_app.hive_subscriptions s ON c.id = s.community_id
    LEFT JOIN hivemind_app.hive_roles r ON r.account_id = s.account_id
        AND r.community_id = c.id
    WHERE s.account_id = __account_id
    ORDER BY COALESCE(role_id, 0) DESC, c.rank;
END
$function$
;