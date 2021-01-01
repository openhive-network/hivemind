DROP FUNCTION IF EXISTS bridge_get_account_posts_by_comments;

CREATE FUNCTION bridge_get_account_posts_by_comments( in _account VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __account_id INT;
  __post_id INT;
BEGIN
  __account_id = find_account_id( _account, True );
  __post_id = find_comment_id( _author, _permlink, True );
  RETURN QUERY SELECT
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
      NULL
  FROM
  (
    SELECT hp1.id
    FROM hive_posts hp1 
    WHERE hp1.author_id = __account_id AND hp1.counter_deleted = 0 AND hp1.depth > 0 AND ( __post_id = 0 OR hp1.id < __post_id )
    ORDER BY hp1.id DESC
    LIMIT _limit
  ) ds
  LATERAL get_post_view_by_id(ds.id) hp
  ORDER BY hp.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;
