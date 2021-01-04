DROP FUNCTION IF EXISTS bridge_get_discussion;

CREATE OR REPLACE 
FUNCTION bridge_get_discussion(_author hive_accounts.name%TYPE, _permlink hive_permlink_data.permlink%TYPE, _observer VARCHAR) RETURNS SETOF bridge_api_post_discussion
AS $function$
DECLARE
    __post_id INT;
    __observer_id INT;
BEGIN
    __post_id = find_comment_id( _author, _permlink, True );
    __observer_id = find_account_id( _observer, True );
    RETURN QUERY
    WITH ds AS --bridge_get_discussion
    (
      WITH RECURSIVE child_posts (id, parent_id) AS
      (
        SELECT
	  hp.id,
	  hp.parent_id,
          blacklist.source
        FROM hive_posts hp
	LEFT OUTER JOIN blacklisted_by_observer_view blacklist on (blacklist.observer_id = __observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE hp.id = __post_id
          AND (NOT EXISTS (SELECT 1 FROM muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp.author_id))
        UNION ALL
        SELECT
          children.id,
          children.parent_id,
          blacklist.source
        FROM hive_posts children 
        LEFT OUTER JOIN blacklisted_by_observer_view blacklist on (blacklist.observer_id = __observer_id AND blacklist.blacklisted_id = children.author_id)
        JOIN child_posts ON children.parent_id = child_posts.id
        JOIN hive_accounts ON children.author_id = hive_accounts.id
        WHERE children.counter_deleted = 0
          AND (NOT EXISTS (SELECT 1 FROM muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = children.author_id))
      )
      SELECT
        hp2.id,
        cp.source
      FROM hive_posts hp2
      JOIN child_posts cp ON cp.id = hp2.id
      ORDER BY hp2.id
      LIMIT 2000
    )
    SELECT
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
        ds.source
    FROM ds,
    LATERAL get_post_view_by_id(ds.id) hp
    ORDER BY ds.id
    LIMIT 2000;
END
$function$ LANGUAGE plpgsql STABLE;
