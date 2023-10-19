DROP TYPE IF EXISTS hivemind_app.bridge_api_list_community_roles CASCADE;
CREATE TYPE hivemind_app.bridge_api_list_community_roles AS (
    name VARCHAR(16),
    role VARCHAR,
    title VARCHAR
);

DROP TYPE IF EXISTS hivemind_app.bridge_api_community_team CASCADE;
CREATE TYPE hivemind_app.bridge_api_community_team AS (
    name VARCHAR,
    role_id SMALLINT,
    title VARCHAR
);

DROP FUNCTION IF EXISTS hivemind_app.bridge_list_community_roles
;
CREATE OR REPLACE FUNCTION hivemind_app.bridge_list_community_roles(
    in _community hivemind_app.hive_communities.name%TYPE,
    in _last hivemind_app.hive_accounts.name%TYPE,
    in _limit INT
)
RETURNS SETOF hivemind_app.bridge_api_list_community_roles
LANGUAGE plpgsql
AS
$function$
DECLARE
    __last_role INT;
    __community_id INT := hivemind_app.find_community_id( _community, True );
    __context hivemind_app.bridge_api_community_context;
    __team hivemind_app.bridge_api_community_team;
BEGIN

    IF _last <> '' THEN
        SELECT INTO __last_role
        COALESCE((
            SELECT role_id
            FROM hivemind_app.hive_roles
            WHERE account_id = (SELECT id from hivemind_app.hive_accounts WHERE name = _last)
            AND hivemind_app.hive_roles.community_id = __community_id
        ),0);

        IF __last_role = 0 THEN
            RAISE EXCEPTION 'invalid last' USING ERRCODE = 'CEHM1';
        END IF;

        RETURN QUERY
        SELECT a.name, hivemind_app.get_role_name(r.role_id), r.title
        FROM hivemind_app.hive_roles r
        JOIN hivemind_app.hive_accounts a ON r.account_id = a.id
        WHERE r.community_id = __community_id
        AND r.role_id != 0
        AND (r.role_id < __last_role OR (r.role_id = __last_role AND a.name > _last))
        ORDER BY r.role_id DESC, name LIMIT _limit;
    ELSE
        RETURN QUERY
        SELECT a.name, hivemind_app.get_role_name(r.role_id), r.title
        FROM hivemind_app.hive_roles r
        JOIN hivemind_app.hive_accounts a ON r.account_id = a.id
        WHERE r.community_id = __community_id
        AND r.role_id != 0
        ORDER BY r.role_id DESC, name LIMIT _limit;
    END IF;


END
$function$
;