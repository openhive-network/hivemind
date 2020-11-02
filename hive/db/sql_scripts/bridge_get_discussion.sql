DROP FUNCTION IF EXISTS get_discussion
;
CREATE OR REPLACE FUNCTION get_discussion(
    in _author hive_accounts.name%TYPE,
    in _permlink hive_permlink_data.permlink%TYPE
)
RETURNS TABLE
(
    id hive_posts.id%TYPE, parent_id hive_posts.parent_id%TYPE, author hive_accounts.name%TYPE, permlink hive_permlink_data.permlink%TYPE,
    title hive_post_data.title%TYPE, body hive_post_data.body%TYPE, category hive_category_data.category%TYPE, depth hive_posts.depth%TYPE,
    promoted hive_posts.promoted%TYPE, payout hive_posts.payout%TYPE, pending_payout hive_posts.pending_payout%TYPE, payout_at hive_posts.payout_at%TYPE,
    is_paidout hive_posts.is_paidout%TYPE, children hive_posts.children%TYPE, created_at hive_posts.created_at%TYPE, updated_at hive_posts.updated_at%TYPE,
    rshares hive_posts_view.rshares%TYPE, abs_rshares hive_posts_view.abs_rshares%TYPE, json hive_post_data.json%TYPE, author_rep hive_accounts.reputation%TYPE,
    is_hidden hive_posts.is_hidden%TYPE, is_grayed BOOLEAN, total_votes BIGINT, sc_trend hive_posts.sc_trend%TYPE,
    acct_author_id hive_posts.author_id%TYPE, root_author hive_accounts.name%TYPE, root_permlink hive_permlink_data.permlink%TYPE,
    parent_author hive_accounts.name%TYPE, parent_permlink_or_category hive_permlink_data.permlink%TYPE, allow_replies BOOLEAN,
    allow_votes hive_posts.allow_votes%TYPE, allow_curation_rewards hive_posts.allow_curation_rewards%TYPE, url TEXT, root_title hive_post_data.title%TYPE,
    beneficiaries hive_posts.beneficiaries%TYPE, max_accepted_payout hive_posts.max_accepted_payout%TYPE, percent_hbd hive_posts.percent_hbd%TYPE,
    curator_payout_value hive_posts.curator_payout_value%TYPE
)
LANGUAGE plpgsql
AS
$function$
DECLARE
    __post_id INT;
BEGIN
    __post_id = find_comment_id( _author, _permlink, True );
    RETURN QUERY
    SELECT
        hpv.id,
        hpv.parent_id,
        hpv.author,
        hpv.permlink,
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
        hpv.created_at,
        hpv.updated_at,
        hpv.rshares,
        hpv.abs_rshares,
        hpv.json,
        hpv.author_rep,
        hpv.is_hidden,
        hpv.is_grayed,
        hpv.total_votes,
        hpv.sc_trend,
        hpv.author_id AS acct_author_id,
        hpv.root_author,
        hpv.root_permlink,
        hpv.parent_author,
        hpv.parent_permlink_or_category,
        hpv.allow_replies,
        hpv.allow_votes,
        hpv.allow_curation_rewards,
        hpv.url,
        hpv.root_title,
        hpv.beneficiaries,
        hpv.max_accepted_payout,
        hpv.percent_hbd,
        hpv.curator_payout_value,
        hpv.is_muted
    FROM
    (
        WITH RECURSIVE child_posts (id, parent_id) AS
        (
            SELECT hp.id, hp.parent_id
            FROM hive_posts hp
            WHERE hp.id = __post_id
            UNION ALL
            SELECT children.id, children.parent_id
            FROM hive_posts children
            JOIN child_posts ON children.parent_id = child_posts.id
            WHERE children.counter_deleted = 0
        )
        SELECT hp2.id
        FROM hive_posts hp2
        JOIN child_posts cp ON cp.id = hp2.id
        ORDER BY hp2.id
    ) ds
    JOIN hive_posts_view hpv ON ds.id = hpv.id
    ORDER BY ds.id
    LIMIT 2000
    ;
END
$function$
;
