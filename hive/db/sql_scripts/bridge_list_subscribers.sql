DROP TYPE IF EXISTS bridge_api_list_subscribers CASCADE;
CREATE TYPE bridge_api_list_subscribers AS (
    name VARCHAR,
    role VARCHAR,
    title VARCHAR,
    created_at VARCHAR(19)
);

DROP FUNCTION IF EXISTS bridge_list_subscribers
;
CREATE OR REPLACE FUNCTION bridge_list_subscribers(
    in _community hive_communities.name%TYPE,
    in _last hive_accounts.name%TYPE,
    in _limit INT
)
RETURNS SETOF bridge_api_list_subscribers
LANGUAGE plpgsql
AS
$function$
DECLARE
    __community_id INT := find_community_id( _community, True );
    __last_id INT := find_subscription_id(_last, _community, True);
BEGIN
    RETURN QUERY
    SELECT ha.name, get_role_name(COALESCE(hr.role_id,0)), hr.title, hs.created_at::VARCHAR(19)
    FROM hive_subscriptions hs
    LEFT JOIN hive_roles hr ON hs.account_id = hr.account_id
    AND hs.community_id = hr.community_id
    JOIN hive_accounts ha ON hs.account_id = ha.id
    WHERE hs.community_id = __community_id
    AND (__last_id = 0 OR (
	hs.id < __last_id
        )
    )
    ORDER BY hs.created_at DESC, hs.id ASC
    LIMIT _limit;
END
$function$
;

