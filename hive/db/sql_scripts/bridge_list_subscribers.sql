DROP TYPE IF EXISTS bridge_api_list_subscribers CASCADE;
CREATE TYPE bridge_api_list_subscribers AS (
    name VARCHAR,
    role_id SMALLINT,
    title VARCHAR,
    created_at VARCHAR(19)
);

DROP FUNCTION IF EXISTS bridge_list_subscribers
;
CREATE OR REPLACE FUNCTION bridge_list_subscribers(
    in _community hive_communities.name%TYPE
)
RETURNS SETOF bridge_api_list_subscribers
LANGUAGE plpgsql
AS
$function$
DECLARE
    __community_id INT := find_community_id( _community, True );
BEGIN

    RETURN QUERY
    SELECT ha.name, hr.role_id, hr.title, hs.created_at::VARCHAR(19)
    FROM hive_subscriptions hs
    LEFT JOIN hive_roles hr ON hs.account_id = hr.account_id
    AND hs.community_id = hr.community_id
    JOIN hive_accounts ha ON hs.account_id = ha.id
    WHERE hs.community_id = __community_id
    ORDER BY hs.created_at DESC, hs.id ASC
    LIMIT 250;
END
$function$
;