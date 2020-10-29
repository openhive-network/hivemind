DROP FUNCTION IF EXISTS condenser_get_post_discussions_by_payout;

CREATE FUNCTION condenser_get_post_discussions_by_payout( in _tag VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __category_id INT;
BEGIN
  __post_id = find_comment_id( _author, _permlink, True );
  __category_id = ( SELECT id FROM hive_category_data WHERE category = _tag );
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
      hp.is_muted
    FROM hive_posts_view hp
    WHERE hp.is_paidout = '0' AND hp.depth = 0 AND ( __category_id = 0 OR hp.category_id = __category_id )
    ORDER BY (hp.payout+hp.pending_payout) DESC, hp.id DESC LIMIT _limit;
END
$function$
language plpgsql STABLE;
