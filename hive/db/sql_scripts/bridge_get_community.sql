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
    context JSON,
    team JSON
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
    __context JSON := '{}'::json;
BEGIN
    IF _observer <> '' THEN
        __observer_id = find_account_id( _observer, True );
        __context= bridge_get_community_context(_observer, _name);
    END IF;

    RETURN QUERY SELECT
        hc.id,
        hc.name,
        COALESCE(NULLIF(hc.title,''),CONCAT('@',hc.name))::VARCHAR(32),
        hc.about,
        hc.lang,
        hc.type_id,
        hc.is_nsfw,
        hc.subscribers,
        hc.created_at::VARCHAR(19),
        hc.sum_pending,
        hc.num_pending,
        hc.num_authors,
        hc.avatar_url,
        hc.description,
        hc.flag_text,
        hc.settings::JSON,
        __context,
        (SELECT json_agg(json_build_array(a.name, get_role_name(r.role_id), r.title) ORDER BY r.role_id DESC, r.account_id DESC)
            FROM hive_roles r
            JOIN hive_accounts a ON r.account_id = a.id
            WHERE r.community_id = __community_id
            AND r.role_id BETWEEN 4 AND 8
        )
    FROM hive_communities hc
    WHERE hc.id = __community_id
    GROUP BY hc.id
    ;

END
$function$
;