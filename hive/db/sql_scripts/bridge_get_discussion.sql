DROP FUNCTION IF EXISTS bridge_get_discussion;
CREATE OR REPLACE FUNCTION public.bridge_get_discussion(_author character varying, _permlink character varying, _observer character varying)
 RETURNS SETOF bridge_api_post_discussion
AS $function$
DECLARE
    __post_id INT;
    __observer_id INT;
BEGIN
    __post_id = find_comment_id( _author, _permlink, True );
    __observer_id = find_account_id( _observer, True );
    RETURN QUERY
    SELECT -- bridge_get_discussion
        hpv.id,
        hpv.author,
        hpv.parent_author,
        hpv.author_rep,
        hpv.root_title,
        hpv.beneficiaries,
        hpv.max_accepted_payout,
        hpv.percent_hbd,
        hpv.url,
        hpv.permlink,
        hpv.parent_permlink_or_category,
        hpv.title,
        hpv.body,
        hpv.category,
        hpv.depth,
        hpv.promoted,
        hpv.payout,
        hpv.pending_payout,
        hpv.payout_at,
        hpv.is_paidout,
        hpv.children,
        hpv.votes,
        hpv.created_at,
        hpv.updated_at,
        hpv.rshares,
        hpv.abs_rshares,
        hpv.json,
        hpv.is_hidden,
        hpv.is_grayed,
        hpv.total_votes,
        hpv.sc_trend,
        hpv.role_title,
        hpv.community_title,
        hpv.role_id,
        hpv.is_pinned,
        hpv.curator_payout_value,
        hpv.is_muted,
        hpv.parent_id,
        ds.source
    FROM
    (
        WITH RECURSIVE child_posts (id, parent_id) AS
        (
            SELECT hp.id, hp.parent_id, blacklisted_by_observer_view.source as source
            FROM hive_posts hp left outer join blacklisted_by_observer_view on (blacklisted_by_observer_view.observer_id = __observer_id AND blacklisted_by_observer_view.blacklisted_id = hp.author_id)
            WHERE hp.id = __post_id
            AND (NOT EXISTS (SELECT 1 FROM muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp.author_id))
            UNION ALL
            SELECT children.id, children.parent_id, blacklisted_by_observer_view.source as source
            FROM hive_posts children left outer join blacklisted_by_observer_view on (blacklisted_by_observer_view.observer_id = __observer_id AND blacklisted_by_observer_view.blacklisted_id = children.author_id)
            JOIN child_posts ON children.parent_id = child_posts.id
            JOIN hive_accounts ON children.author_id = hive_accounts.id
            WHERE children.counter_deleted = 0
            AND (NOT EXISTS (SELECT 1 FROM muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = children.author_id))
        )
        SELECT hp2.id, cp.source
        FROM hive_posts hp2
        JOIN child_posts cp ON cp.id = hp2.id
        ORDER BY hp2.id
    ) ds,
 LATERAL get_post_view_by_id(ds.id) hpv
    ORDER BY ds.id
    LIMIT 2000;
END
$function$ LANGUAGE plpgsql STABLE;
