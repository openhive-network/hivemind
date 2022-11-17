DROP FUNCTION IF EXISTS condenser_get_content;
CREATE FUNCTION condenser_get_content( in _author VARCHAR, in _permlink VARCHAR )
RETURNS SETOF condenser_api_post_ex
AS
$function$
DECLARE
  __post_id INT;
BEGIN
  __post_id = find_comment_id( _author, _permlink, True );
  RETURN QUERY 
  SELECT
      hp.id,
      hp.author,
      hp.permlink,
      hp.author_rep,
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
      hp.net_votes,
      hp.total_vote_weight,
      hp.parent_author,
      hp.parent_permlink_or_category,
      hp.curator_payout_value,
      hp.root_author,
      hp.root_permlink,
      hp.max_accepted_payout,
      hp.percent_hbd,
      hp.allow_replies,
      hp.allow_votes,
      hp.allow_curation_rewards,
      hp.beneficiaries,
      hp.url,
      hp.root_title,
      hp.active,
      hp.author_rewards
    FROM get_post_view_by_id(__post_id) hp;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS condenser_get_content_replies;
CREATE FUNCTION condenser_get_content_replies( in _author VARCHAR, in _permlink VARCHAR )
RETURNS SETOF condenser_api_post_ex
AS
$function$
DECLARE
  __post_id INT;
BEGIN
  __post_id = find_comment_id( _author, _permlink, True );
  RETURN QUERY 
  WITH replies AS MATERIALIZED -- condenser_get_content_replies
  (
    SELECT id 
    FROM live_posts_comments_view hp 
    WHERE hp.parent_id = __post_id 
    ORDER BY hp.id
    LIMIT 5000
  )
  SELECT
      hp.id,
      hp.author,
      hp.permlink,
      hp.author_rep,
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
      hp.net_votes,
      hp.total_vote_weight,
      hp.parent_author,
      hp.parent_permlink_or_category,
      hp.curator_payout_value,
      hp.root_author,
      hp.root_permlink,
      hp.max_accepted_payout,
      hp.percent_hbd,
      hp.allow_replies,
      hp.allow_votes,
      hp.allow_curation_rewards,
      hp.beneficiaries,
      hp.url,
      hp.root_title,
      hp.active,
      hp.author_rewards
    FROM replies,
    LATERAL get_post_view_by_id(replies.id) hp
    ORDER BY hp.id;
END
$function$
language plpgsql STABLE;
