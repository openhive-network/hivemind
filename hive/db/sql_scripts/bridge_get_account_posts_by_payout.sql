DROP FUNCTION IF EXISTS hivemind_app.bridge_get_account_posts_by_payout;

CREATE FUNCTION hivemind_app.bridge_get_account_posts_by_payout( in _account VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF hivemind_app.bridge_api_post
AS
$function$
DECLARE
  __account_id INT;
  __post_id INT;
  __payout_limit hivemind_app.hive_posts.payout%TYPE;
BEGIN
  __account_id = hivemind_app.find_account_id( _account, True );
  __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
  IF __post_id <> 0 THEN
      SELECT ( hp.payout + hp.pending_payout ) INTO __payout_limit FROM hivemind_app.hive_posts hp WHERE hp.id = __post_id;
  END IF;
  RETURN QUERY
  WITH payouts AS
  (  
    SELECT 
      id,
      (hp.payout + hp.pending_payout) as total_payout
    FROM hivemind_app.live_posts_comments_view hp
    WHERE
      hp.author_id = __account_id
      AND NOT hp.is_paidout
      AND ( __post_id = 0 OR (hp.payout + hp.pending_payout) < __payout_limit
                          OR ((hp.payout + hp.pending_payout) = __payout_limit AND hp.id < __post_id) )
    ORDER BY (hp.payout + hp.pending_payout) DESC, hp.id DESC
    LIMIT _limit
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
      NULL
  FROM payouts,
  LATERAL hivemind_app.get_post_view_by_id(payouts.id) hp
  ORDER BY payouts.total_payout DESC, payouts.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;
