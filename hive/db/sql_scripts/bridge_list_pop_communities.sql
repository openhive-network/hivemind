DROP TYPE IF EXISTS bridge_api_list_pop_communities CASCADE;
CREATE TYPE bridge_api_list_pop_communities AS (
    name VARCHAR,
    title VARCHAR
);

DROP FUNCTION IF EXISTS bridge_list_pop_communities
;
CREATE OR REPLACE FUNCTION bridge_list_pop_communities(
    in _limit INT
)
RETURNS SETOF bridge_api_list_pop_communities
LANGUAGE plpgsql
AS
$function$
BEGIN
    RETURN QUERY
    SELECT name, title
    FROM hivemind_app.hive_communities
    JOIN (
        SELECT community_id, COUNT(*) newsubs
        FROM hivemind_app.hive_subscriptions
        WHERE created_at > head_block_time() - INTERVAL '1 MONTH'
        GROUP BY community_id
    ) stats
    ON stats.community_id = id
    ORDER BY newsubs DESC, id DESC
    LIMIT _limit;
END
$function$
;