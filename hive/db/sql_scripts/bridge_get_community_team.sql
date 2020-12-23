DROP TYPE IF EXISTS bridge_api_community_team CASCADE;
CREATE TYPE bridge_api_community_team AS (
    name VARCHAR,
    role_id SMALLINT,
    title VARCHAR
);

DROP FUNCTION IF EXISTS bridge_get_community_team
;
CREATE OR REPLACE FUNCTION bridge_get_community_team(
    in _name hive_communities.name%TYPE
)
RETURNS SETOF bridge_api_community_team
LANGUAGE plpgsql
AS
$function$
DECLARE
    __community_id INT := find_community_id( _name, True );
BEGIN

    RETURN QUERY SELECT a.name, r.role_id, r.title
    FROM hive_roles r
    JOIN hive_accounts a ON r.account_id = a.id
    WHERE r.community_id = __community_id
    AND r.role_id BETWEEN 4 AND 8
    ORDER BY r.role_id DESC, r.account_id DESC
    ;

END
$function$
;