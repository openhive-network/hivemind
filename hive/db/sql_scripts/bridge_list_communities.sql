DROP TYPE IF EXISTS bridge_api_list_communities CASCADE;
CREATE TYPE bridge_api_list_communities AS (
    id INTEGER,
    name VARCHAR(16),
    title VARCHAR(32),
    about VARCHAR(120),
    lang CHAR(2),
    type_id SMALLINT,
    is_nsfw BOOLEAN,
    subscribers INTEGER,
    sum_pending INTEGER,
    num_pending INTEGER,
    num_authors INTEGER,
    created_at TIMESTAMP,
    avatar_url VARCHAR(1024),
    context JSON,
    admins VARCHAR ARRAY
);

DROP FUNCTION IF EXISTS bridge_list_communities_by_rank
;
CREATE OR REPLACE FUNCTION bridge_list_communities_by_rank(
    in _observer hive_accounts.name%TYPE,
    in _last hive_accounts.name%TYPE,
    in _search VARCHAR,
    in _limit INT
)
RETURNS SETOF bridge_api_list_communities
LANGUAGE plpgsql
AS
$function$
DECLARE
    __last_id INT := find_community_id( _last, True );
    __rank hive_communities.rank%TYPE = 0;
BEGIN
    IF ( _last <> '' ) THEN
        SELECT hc.rank INTO __rank FROM hive_communities hc WHERE hc.id = __last_id;
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
        hc.sum_pending,
        hc.num_pending,
        hc.num_authors,
        hc.created_at,
        hc.avatar_url,
        bridge_get_community_context(_observer, hc.name),
        array_agg(ha.name ORDER BY ha.name)
    FROM hive_communities as hc
    LEFT JOIN hive_roles hr ON hr.community_id = hc.id AND hr.role_id = 6
    LEFT JOIN hive_accounts ha ON hr.account_id = ha.id
    WHERE hc.rank > __rank
    AND (_search IS NULL OR to_tsvector('english', hc.title || ' ' || hc.about) @@ plainto_tsquery(_search))
    GROUP BY hc.id
    ORDER BY hc.rank ASC
    LIMIT _limit
    ;
END
$function$
;

DROP FUNCTION IF EXISTS bridge_list_communities_by_new
;
CREATE OR REPLACE FUNCTION bridge_list_communities_by_new(
    in _observer hive_accounts.name%TYPE,
    in _last hive_accounts.name%TYPE,
    in _search VARCHAR,
    in _limit INT
)
RETURNS SETOF bridge_api_list_communities
LANGUAGE plpgsql
AS
$function$
DECLARE
    __last_id INT := find_community_id( _last, True );
BEGIN
    RETURN QUERY SELECT
        hc.id,
        hc.name,
        COALESCE(NULLIF(hc.title,''),CONCAT('@',hc.name))::VARCHAR(32),
        hc.about,
        hc.lang,
        hc.type_id,
        hc.is_nsfw,
        hc.subscribers,
        hc.sum_pending,
        hc.num_pending,
        hc.num_authors,
        hc.created_at,
        hc.avatar_url,
        bridge_get_community_context(_observer, hc.name),
        array_agg(ha.name ORDER BY ha.name)
    FROM hive_communities as hc
    LEFT JOIN hive_roles hr ON hr.community_id = hc.id AND hr.role_id = 6
    LEFT JOIN hive_accounts ha ON hr.account_id = ha.id
    WHERE (__last_id = 0 OR hc.id < __last_id)
    AND (_search IS NULL OR to_tsvector('english', hc.title || ' ' || hc.about) @@ plainto_tsquery(_search))
    GROUP BY hc.id
    ORDER BY hc.id DESC
    LIMIT _limit
    ;
END
$function$
;

DROP FUNCTION IF EXISTS bridge_list_communities_by_subs
;
CREATE OR REPLACE FUNCTION bridge_list_communities_by_subs(
    in _observer hive_accounts.name%TYPE,
    in _last hive_accounts.name%TYPE,
    in _search VARCHAR,
    in _limit INT
)
RETURNS SETOF bridge_api_list_communities
LANGUAGE plpgsql
AS
$function$
DECLARE
    __last_id INT := find_community_id( _last, True );
    __subscribers hive_communities.subscribers%TYPE;
BEGIN
    IF ( _last <> '' ) THEN
        SELECT hc.subscribers INTO __subscribers FROM hive_communities hc WHERE hc.id = __last_id;
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
        hc.sum_pending,
        hc.num_pending,
        hc.num_authors,
        hc.created_at,
        hc.avatar_url,
        bridge_get_community_context(_observer, hc.name),
        array_agg(ha.name ORDER BY ha.name)
    FROM hive_communities as hc
    LEFT JOIN hive_roles hr ON hr.community_id = hc.id AND hr.role_id = 6
    LEFT JOIN hive_accounts ha ON hr.account_id = ha.id
    WHERE (__last_id = 0 OR hc.subscribers < __subscribers OR (hc.subscribers = __subscribers AND hc.id < __last_id))
    AND (_search IS NULL OR to_tsvector('english', hc.title || ' ' || hc.about) @@ plainto_tsquery(_search))
    GROUP BY hc.id
    ORDER BY hc.subscribers DESC, hc.id DESC
    LIMIT _limit
    ;
END
$function$
;