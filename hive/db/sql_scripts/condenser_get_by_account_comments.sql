DROP FUNCTION IF EXISTS hivemind_app.condenser_get_by_account_comments;

CREATE OR REPLACE FUNCTION hivemind_app.condenser_get_by_account_comments( in _author VARCHAR, in _permlink VARCHAR, in _limit INTEGER)
RETURNS SETOF hivemind_app.bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER := 0;
  __author_id INTEGER := 0;
BEGIN
  __author_id = hivemind_app.find_account_id(_author, True);
  IF _permlink <> '' THEN
    __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
  END IF;

  RETURN QUERY 
  WITH comments AS MATERIALIZED -- condenser_get_by_account_comments
  (
    SELECT id
    FROM hivemind_app.live_comments_view hp
    WHERE hp.author_id = __author_id
      AND ( ( __post_id = 0 ) OR ( hp.id <= __post_id ) ) 
    ORDER BY hp.id DESC
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
    FROM comments,
    LATERAL hivemind_app.get_post_view_by_id(comments.id) hp
    ORDER BY hp.id DESC
    LIMIT _limit;
END
$function$
language plpgsql STABLE;
