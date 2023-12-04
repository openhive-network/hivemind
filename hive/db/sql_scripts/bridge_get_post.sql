DROP FUNCTION IF EXISTS hivemind_app.bridge_get_post;

CREATE FUNCTION hivemind_app.bridge_get_post( in _author VARCHAR, in _permlink VARCHAR )
RETURNS SETOF hivemind_app.bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
BEGIN
  __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
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
      NULL,
      hp.muted_reasons
  FROM hivemind_app.get_post_view_by_id(__post_id) hp;
END
$function$
language plpgsql STABLE;
