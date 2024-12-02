DROP FUNCTION IF EXISTS hivemind_app.bridge_get_discussion;
CREATE OR REPLACE FUNCTION hivemind_app.bridge_get_discussion(_author character varying, _permlink character varying, _observer character varying)
 RETURNS SETOF hivemind_app.bridge_api_post_discussion
AS $function$
DECLARE
    __post_id INT;
    __observer_id INT;
BEGIN
    __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
    __observer_id = hivemind_app.find_account_id( _observer, True );
    RETURN QUERY
    SELECT -- bridge_get_discussion
        hp.id,
        hp.author,
        hp.parent_author,
        hp.author_rep,
        hp.root_title,
        hp.beneficiaries,
        hp.max_accepted_payout,
        hp.percent_hbd,
        hp.url,
        hp.permlink,
        hp.parent_permlink_or_category,
        hp.title,
        hp.body,
        hp.category,
        hp.depth,
        hp.promoted,
        hp.payout,
        hp.pending_payout,
        hp.payout_at,
        hp.is_paidout,
        hp.children,
        hp.votes,
        hp.created_at,
        hp.updated_at,
        hp.rshares,
        hp.abs_rshares,
        hp.json,
        hp.is_hidden,
        hp.is_grayed,
        hp.total_votes,
        hp.sc_trend,
        hp.role_title,
        hp.community_title,
        hp.role_id,
        hp.is_pinned,
        hp.curator_payout_value,
        hp.is_muted,
        hp.parent_id,
        hp.source,
        hp.muted_reasons
    FROM
    (
        WITH RECURSIVE child_posts (id, parent_id) AS MATERIALIZED
        (
            SELECT hp.id, hp.parent_id
            FROM hivemind_app.live_posts_comments_view hp 
            WHERE hp.id = __post_id
            AND (NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp.author_id))
            UNION ALL
            SELECT children.id, children.parent_id
            FROM hivemind_app.live_posts_comments_view children
            JOIN child_posts ON children.parent_id = child_posts.id
            JOIN hivemind_app.hive_accounts ON children.author_id = hivemind_app.hive_accounts.id
            AND (NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = children.author_id))
        )
        SELECT hp2.id
        FROM hivemind_app.hive_posts hp2
        JOIN child_posts cp ON cp.id = hp2.id
        ORDER BY hp2.id
    ) ds,
    LATERAL hivemind_app.get_full_post_view_by_id(ds.id, __observer_id) hp
    ORDER BY ds.id
    LIMIT 2000;
END
$function$ LANGUAGE plpgsql STABLE;
