DROP TYPE IF EXISTS hivemind_app.bridge_api_list_subscribers CASCADE;
CREATE TYPE hivemind_app.bridge_api_list_subscribers AS (
    name VARCHAR,
    role VARCHAR,
    title VARCHAR,
    created_at TIMESTAMP WITHOUT TIME ZONE
);

DROP FUNCTION IF EXISTS hivemind_app.bridge_list_subscribers
;
CREATE OR REPLACE FUNCTION hivemind_app.bridge_list_subscribers(
    in _community hivemind_app.hive_communities.name%TYPE,
    in _last hivemind_app.hive_accounts.name%TYPE,
    in _limit INT
)
RETURNS SETOF hivemind_app.bridge_api_list_subscribers
LANGUAGE plpgsql
AS
$function$
DECLARE
    __community_id INT := hivemind_app.find_community_id( _community, True );
    __last_id INT := hivemind_app.find_subscription_id(_last, _community, True);
BEGIN
    RETURN QUERY
    SELECT ha.name, hivemind_app.get_role_name(COALESCE(hr.role_id,0)), hr.title, hs.created_at
    FROM hivemind_app.hive_subscriptions hs
    LEFT JOIN hivemind_app.hive_roles hr ON hs.account_id = hr.account_id
    AND hs.community_id = hr.community_id
    JOIN hivemind_app.hive_accounts ha ON hs.account_id = ha.id
    WHERE hs.community_id = __community_id
    AND (__last_id = 0 OR (
        hs.id < __last_id
        )
    )
    ORDER BY ha.name ASC
    LIMIT _limit;
END
$function$
;

