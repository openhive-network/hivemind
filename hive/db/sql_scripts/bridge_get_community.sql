DROP TYPE IF EXISTS bridge_api_community CASCADE;
CREATE TYPE bridge_api_community AS (
    id INTEGER,
    name VARCHAR(16),
    title VARCHAR(32),
    about VARCHAR(120),
    lang CHAR(2),
    type_id SMALLINT,
    is_nsfw BOOLEAN,
    subscribers INTEGER,
    created_at VARCHAR(19),
    sum_pending Integer,
    num_pending Integer,
    num_authors Integer,
    avatar_url VARCHAR(1024),
    description VARCHAR(5000),
    flag_text VARCHAR(5000),
    settings JSON,
    context bridge_api_community_context,
    team bridge_api_community_team
);

DROP FUNCTION IF EXISTS bridge_get_community
;
CREATE OR REPLACE FUNCTION bridge_get_community(
    in _name hive_communities.name%TYPE,
    in _observer hive_accounts.name%TYPE
)
RETURNS SETOF bridge_api_community
LANGUAGE plpgsql
AS
$function$
DECLARE
    __observer_id INT;
    __community_id INT := find_community_id( _name, True );
    __context bridge_api_community_context;
    __team bridge_api_community_team;
BEGIN
    IF _observer <> '' THEN
        __observer_id = find_account_id( _observer, True );
        __context= bridge_get_community_context(_observer, _name);
    END IF;

    SELECT a.name as name, r.role_id, r.title
    INTO __team
    FROM hive_roles r
    JOIN hive_accounts a ON r.account_id = a.id
    WHERE r.community_id = __community_id
    AND r.role_id BETWEEN 4 AND 8
    ORDER BY r.role_id DESC, r.account_id DESC
    ;

    RETURN QUERY SELECT
        id,
        name,
        COALESCE(NULLIF(title,''),CONCAT('@',name))::VARCHAR(32),
        about,
        lang,
        type_id,
        is_nsfw,
        subscribers,
        created_at::VARCHAR(19),
        sum_pending,
        num_pending,
        num_authors,
        avatar_url,
        description,
        flag_text,
        settings::JSON,
        __context,
        __team
    FROM hive_communities
    WHERE id = __community_id
    ;

END
$function$
;